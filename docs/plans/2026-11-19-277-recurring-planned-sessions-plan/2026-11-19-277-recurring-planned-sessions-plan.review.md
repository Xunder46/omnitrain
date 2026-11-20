# Review: 277 recurring planned sessions · P1, P2, P3a, P3b, P4 · 8ec6f42..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 3 · tests: not run this run (brief says the governor did: recurrence_rule 12, state 20 (Mock and Hive), day list 9, three-choice dialog 8, sheet 10 — all green; analyze 174 vs baseline 176, 0 errors; ui_standards and docs contract tests green; plan-lint clean)
Diff vs Predicted Files: conforms for this plan's scope (all predicted files present). The working tree also carries files of plans 278/279 (backup/settings, save-as-routine) — ignored per the brief.

## Brief questions

1. **Series edit/delete never touch history.** `updateSeriesFrom` (`calendar_state.dart:322`) and `deleteSeriesFrom` (`:365`) skip completed rows, linked rows and past-day rows (`isCompleted`, `linkedSessionId != null`, `isPastDay`). `deleteSeriesFrom` deletes `from` itself even on a past day (the missed plan the user pointed at) and keeps later past-day rows — guarded by `S-27730`. The UI only opens the edit sheet for today-or-future rows (`day_session_list_screen.dart:179` `isEditable = _isTodayOrFuture`), so `updateSeriesFrom`'s past-day guard is belt-and-braces. Completed rows get no delete affordance (`onDelete: null`). No path changes a row the user did not point at. Guarded by S-27713, S-27714, S-27729, S-27730.
2. **No per-row reload.** `CalendarState` has no repository/revision subscription (grep: no `addListener`/stream in the file); the only reader is the screen's `ListenableBuilder(listenable: widget.calendarState)`. `createRecurringPlannedSessions` writes sequentially and calls `_loadMonth()` once (`:319`), so one create notifies twice (start/finally, the known `_loadMonth` shape) — guarded by the `_CountingRepo` spy in S-27711 (Mock only). While the up-to-366 writes run the sheet is already closed (`showModalBottomSheet` returned before the awaits) and the day list simply shows stale data until the reload; the bottom CTA stays enabled and there is no busy guard, but Hive writes are fast and the cost was decided in D-27704 — noted, not a finding.
3. **Two-write Repeat-on edit is not atomic and not surfaced.** `updatePlannedSession` commits the rule-stamped row, then `createRecurringPlannedSessions` creates the later dates (`day_session_list_screen.dart:423-450`). If the second throws, the first stays: the plan becomes a coherent series of one (S-27712 shape) and the user gets no message — the exception is unhandled. Plan 266's "failed saves say so" explicitly excluded these screens (its open item: other saves "were not part of this item"), and `_addPlanned`/`_editPlanned`/`_deletePlanned` never caught errors before this change either — so no existing decision is violated, but the new path is wider. Finding 1 below.
4. **Watch unaffected.** `buildPlannedDown` (`watch_reference_sync.dart:199`) sends every uncompleted, unlinked row in the yesterday..day+14 window; no one-plan-per-routine-per-day assumption exists in the builder, no rule field on the wire, ties sorted by date then id. `completePlanFor` (`calendar_state.dart:435`) picks the earliest-created unstarted plan of the routine for that day — a same-day second plan resolves deterministically (pre-existing rule, unchanged). Series rows travel as plain rows. No finding.
5. **UI standards hold.** FilterChip and the Ends/until buttons set explicit `shape:` from `OmniTheme.buttonUtilityRadius`/`buttonBorderRadius` (`_modeButtonShape` is pre-existing); all colours are theme-derived (`theme.colorScheme`/`themeColors` with `withValues`), no hex literals; no raw Card/SnackBar/IconButton added; the raw `Switch` has precedent in this same file and Settings; `NumericFieldWithDoneBar` is the shared piece; the dialog reuses `_dialogActionStyle`/`_dialogActionShape`. No allowlist entry added, no ratchet raised (the allowlist file is not in the diff). No finding.

## Findings

1. [Minor] `lib/features/calendar/day_session_list_screen.dart:423-450` — the Repeat-on edit path writes twice with no error handling: a failed `createRecurringPlannedSessions` after a successful `updatePlannedSession` leaves the row stamped with the rule text (a silent series of one), the sheet is closed and the user sees no message. Consistent with this file's existing unguarded CRUD handlers (plan 266 excluded them), but the two-write path is new. Fix: wrap the second write in try/catch and show `OmniMessage.error(context, 'Could not save. Try again.')` like `_startPlanned` does. Guard: a state/screen test that makes the repo throw on the second write.
2. [Minor] `test/recurrence_rule_test.dart:414` — a second test is labelled `S-27710 summary renders one plain-words line`, but S-27710 is the round-trip scenario (line 268); the duplicate id makes the plan↔test map ambiguous and the summary item is plan task P1.3, not a scenario. Fix: rename to a non-scenario label (e.g. `P1.3 summary renders one plain-words line`).
3. [Minor] plan file (`2026-11-19-277-recurring-planned-sessions-plan.md`), scenario table — the delivered test set includes S-27730 and the suffixed variants S-27711b, S-27718b, S-27725b, S-27726b, which the plan's scenario table and its "29 ≤ 30" budget note do not list; `docs/calendar_periods.md` cites them. The coverage is good and the tests exist (verified by name), but the plan is now stale against what it governs. Fix: add S-27730 and the suffix variants to the plan's scenario table (the budget note then needs its count corrected).

## Assumption Log rulings

The plan's Assumption Log table is empty; its content lives in "Open questions (architect)" 1–7, each carrying a resolution. Rulings: OQ2 (one-reload assertion interpreted as one `_loadMonth` cycle) — ratified, the S-27711 spy implements exactly that; OQ3 (summary always shows the session count, appends `until` only for a date end) — ratified, implemented as resolved in `RecurrenceRule.summary`; OQ4 (D-27711/D-27712 and the `skipFirst` parameter) — ratified, needed for S-27724; OQ1, OQ5–OQ7 — informational, no action. No unresolved entry; no finding.

## Scenario coverage

- S-27701..S-27710 → `test/recurrence_rule_test.dart` tests `S-27701`..`S-27710` (lines 40, 55, 72, 89, 108, 127, 155, 194, 212, 268; S-27709 uses the source-text guard plus a runtime midnight check).
- S-27711, S-27712, S-27713, S-27714, S-27715, S-27716, S-27727, S-27729 → `test/recurring_planned_sessions_state_test.dart` over `harnessFactories` (Mock and Hive; reload count on Mock).
- S-27717, S-27718, S-27719, S-27720, S-27721, S-27724, S-27725, S-27726 → `test/recurring_planned_sessions_sheet_test.dart` groups `S-27717`..`S-27726` (+ S-27718b, S-27726b).
- S-27722, S-27723, S-27728 → `test/recurring_planned_sessions_day_list_test.dart` (Mock-first; series seeded through `createRecurringPlannedSessions`).
- Extra coverage beyond the table: S-27730, S-27711b, S-27718b, S-27725b, S-27726b (see Finding 3).
No scenario MISSING.

## Docs delta

- `docs/calendar_periods.md` REMOVED "No recurrence behavior yet (model extension point exists)." -> applied
- `docs/calendar_periods.md` MODIFIED `- recurrenceRule (nullable placeholder)` -> applied
- `docs/calendar_periods.md` MODIFIED invariant "placeholder field that is never read" -> applied
- `docs/calendar_periods.md` ADDED section "Repeating planned sessions" -> applied
- `docs/widget_catalog.md` MODIFIED `ConfirmationDialog` row (`showThreeChoice`) -> applied
- `docs/calendar_periods.md` MODIFIED "Simple CRUD for planned sessions and periods." -> applied
- `docs/calendar_periods.md` MODIFIED "Handles planned session CRUD and the recurring-series actions" -> applied
- `docs/design_system.md` MODIFIED "Every `ConfirmationDialog` shape builds its action buttons" -> applied

Every behaviour sentence in the new docs section names a test; every cited test name was verified to exist in the test files this run (state, sheet, day list, dialog, rule). Doc edits the table does not name: none.

## Standards seen, not fixed

None.
