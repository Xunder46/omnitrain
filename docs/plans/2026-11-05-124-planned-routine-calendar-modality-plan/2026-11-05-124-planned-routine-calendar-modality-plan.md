# Feature: 124 — A planned routine shows its Focus in the calendar (bug fix)

> Status: Iteration 1 ready (one owner question, Q1, with a default the plan builds against)
> Next handoff: crew-builder-app (Phase 0: red tests)
> Binding conventions: `docs/global_conventions.md`; `docs/documentation_standard.md` (Phase 2);
> `docs/calendar_periods.md`, `docs/my_routines.md`, `.github/copilot/pr-scope-budget.md`.
> Track: phone only (`lib/`). No schema, no migration, no data-version bump.
> Relation to plan 122 (`docs/plans/2026-11-05-122-routine-session-modality-plan/`, read-only here): see "Order and conflicts".
> Evidence → `…-124-…-plan.evidence.md`; review → `…-124-…-plan.review.md`.

## Overview

A routine scheduled for a day (a `PlannedSession`, not started) is drawn with the Free Training
colour even when the routine has a Focus Modality. Root cause (verified in code):
- The planning form stores `modality: null` for a routine plan
  (`lib/features/calendar/day_session_list_screen.dart:922`, `_mode == 'free' ? _selectedModality : null`),
  and only `routineTemplateId` identifies the routine (`models.dart:1461` `PlannedSession`).
- `CalendarEntry.fromPlannedSession` copies `p.modality` verbatim (`lib/state/calendar/calendar_state.dart:45`).
- Every calendar surface then reads `entry.modality`: month-grid dot colour (`calendar_screen.dart:600`,
  `_Dot`), day-list card colour (`day_session_list_screen.dart:429`), and — via `labelForModality(null)`
  = "Free Training" (`modality_color_utils.dart:25-27`) — the day-list fallback title (:542, only when a
  planned entry has neither title nor template) and subtitle (:548; but a planned routine's subtitle is
  currently just "Planned" (:555-557), so the Focus name is not shown at all).

What the owner sees today: a planned Isometric routine is a Free-Training-coloured outlined dot on the
month grid and a Free-Training-coloured card in the day list. (Honest note: the words "Free Training" are
not printed on a planned routine card today; the wrong colour is. Q1 covers adding the Focus name.)

Deleting a routine already deletes its planned entries (`routine_state.dart:266-276`,
`deletePlannedSessionsByTemplateId`), so "routine deleted after planning" can only arise from orphan or
synced rows; it is handled, not common.

## What the owner should know (plain language)

1. A planned routine takes its Focus's colour on the month grid and in the day list, and (Q1) the day-list
   card says e.g. "Isometric / Stretching · Planned".
2. It always follows the routine's Focus **today**. If you change the routine's Focus after planning, the
   planned day changes colour with it (a plan is a future intent, not a record). Once the workout is done
   and saved, plan 122's rule applies instead (the finished session keeps the Focus it was started with).
3. A routine with no Focus ("Mixed / Not set") stays Free Training coloured. Plans for a plain modality
   (not a routine) are untouched.
4. The monthly breakdown chips count only completed sessions, so they do not change; a planned workout
   never appears in them.
5. Nothing is rewritten on your device: no one-off clean-up script, no new data version.

## Questions (the plan builds against the default)

**Q1. Show the Focus name on a planned routine's day-list card?** Today the card's second line is just
"Planned". **Default: yes** — "Isometric / Stretching · Planned" (same wording as free-training plans:
`<modality> · <state>`); a no-Focus routine keeps just "Planned". Alternative: colour only.

## Resolved Decisions (Ledger)

- **D-12401 Technical choice (one line): resolve at display time from `routineTemplateId` → template
  `focusModality`, in `CalendarState`; do NOT stamp the planned row.** Evidence: (a) stamping at planning
  time needs a back-fill for every existing planned row — a second one-off migration the owner wants to
  avoid; (b) a stamp goes stale when the routine's Focus is edited, and the owner-visible rule for a plan is
  "follows the routine"; (c) display-time resolution fixes every existing planned row with zero data
  writes; (d) all surfaces (grid, list, breakdown) already read `CalendarEntry.modality`, so one resolution
  point fixes them all.
- **D-12402 Resolution point.** `CalendarState._loadMonth` (`calendar_state.dart:~120-160`) builds the
  month's entries. When at least one unlinked planned entry has a non-null `routineTemplateId`, it calls
  `_repository.getTemplates()` once (not per entry; not at all when there are none) and builds
  `id → focusModality`. `CalendarEntry.fromPlannedSession(p, {String? routineFocus})` sets
  `modality = routineFocus ?? p.modality`. `PlannedSession` rows are never written by this path.
  Repository interface only (`getTemplates`, `workout_repository.dart:190`); no new method.
- **D-12403 Cases.** Template has Focus → that Focus (copied verbatim). Template has no Focus (null or
  empty string) → `p.modality` (null for routine plans) → Free. Template id not found → `p.modality` → Free;
  no throw; title stays "Custom Routine" (:535). Plain modality plan (`routineTemplateId == null`) →
  `p.modality`, unchanged. Empty-string Focus is treated as no Focus.
- **D-12404 Past and completed.** A planned routine on a past day, not started, resolves the same way
  (outlined dot, Focus colour). A planned entry already linked to a session is excluded from the grid
  today (:150-153) and stays so; the session's own modality (plan 122) colours it. A planned entry with
  `isCompleted == true` but no link would be counted in `modalityBreakdown` under its resolved Focus
  (consistent with its dot); no code change needed.
- **D-12405 Day list.** `_buildSubtitle` (`day_session_list_screen.dart:546-561`): for a planned routine
  entry, when `entry.modality != null` return `'$modalityLabel  ·  $stateLabel'` (Q1 default); otherwise
  unchanged. Colour (:429) and title (:526-542) need no change: the colour reads the resolved
  `entry.modality`.
- **D-12406 Freshness.** Entries are resolved on each month load / `refresh()`. After editing a routine's
  Focus the calendar shows the new Focus the next time it loads (screen open, month change, or refresh) —
  same freshness as every other calendar value; no listener on `RoutineState` is added.
- **D-12407 No schema, docs-only contract.** `scripts/sqlite_schema.sql`, `models.dart`,
  `data_version.dart`, repositories: untouched. `PlannedSession.modality` doc comment (:1457-1461 region)
  gains one line: a routine plan stores null; its colour is resolved from the routine at display time.
- **D-12408 Test style.** State scenarios: plain `test()` over `harnessFactories`
  (`test/helpers/repository_harness.dart`). The day-list subtitle: Mock-only `testWidgets` in the style of
  `test/screen_widget_test.dart` "DaySessionListScreen". Every test names its S-id.

## Order and conflicts with plan 122

- 122 changes `day_session_list_screen.dart` `_tapPlanned` (≈:280-286, `modality: null` → the routine's
  Focus) and adds a `home_screen.dart` rule and a back-fill. 124 changes `_buildSubtitle`
  (≈:546-561) in the same file, plus `calendar_state.dart` (122 lists it read-only). The hunks are about
  260 lines apart and do not overlap; the tests are in separate new files; neither plan touches the other's
  test file. **Either order merges without conflict.**
- **Recommended order: 122 first, then 124**, because 122 Phase 4 writes one line in
  `docs/calendar_periods.md` ("planned routine entries are not [coloured by their Focus] (pointer
  S-12207)") that 124 makes false. 124 Phase 2 replaces that sentence. If 124 lands first instead, the
  docs-keeper of 122 must NOT write that sentence (hand-over: tell 122's governor), and 122 Phase 4 item 2
  becomes "routine sessions are coloured by their Focus".
- The calendar-start path is not changed by 124: tapping a planned routine still goes through 122's
  `_tapPlanned` branch; 124 only reads the template. S-12409 pins that the planned row is untouched.
- No second migration, no data-version bump (122 owns 18). 124 has no dependence on 122's code at run time:
  122's session stamp and 124's planned resolution read the same field (`focusModality`) independently.

## Feature Invariants

- A `PlannedSession` row is never written by the calendar load or by display resolution.
- A plain-modality plan and a routine with no Focus render exactly as today.
- At most one `getTemplates()` call per month load, none when no routine is planned that month.
- `lib/state` and `lib/features` depend on `WorkoutRepository` only (AGENTS.md invariant grep).

## Requirements → Acceptance Criteria

- AC-1 A planned routine's grid dot and day-list colour follow the routine's Focus (S-12401, S-12405, S-12406, S-12407).
- AC-2 No Focus / missing routine / plain-modality plans unchanged (S-12402, S-12403, S-12404).
- AC-3 Nothing written; cost bounded (S-12408, S-12409).
- AC-4 Breakdown unchanged for incomplete plans (S-12410). Day-list text per Q1 (S-12411).
- AC-5 Docs updated within size band (Phase 2).

## Existing-Functionality Impact

| Surface | Readers | Effect | Guarded by |
|---|---|---|---|
| `CalendarEntry.modality` for planned routines | `calendar_screen.dart:600` (dot), `day_session_list_screen.dart:429/542/548`, `calendar_state.dart:307-317` | Focus colour instead of Free | S-12401-S-12411 |
| `CalendarState._loadMonth` | `calendar_screen`, `session_summary_screen.dart:154`, `records_and_trends_screen.dart:84` | one extra `getTemplates()` only when a routine is planned | S-12408; existing `test/calendar_*` suites |
| Streak / periods | `_computeStreak`, `_loadPeriods` | unaffected (read sessions/periods) | existing `calendar_streak_*` tests |
| Planned start | `day_session_list_screen.dart:280-292` | not touched (122's) | S-12409 |
| Stats / watch / Health | none read planned modality | unaffected | — |

## UI Standards Impact

No new widgets. `day_session_list_screen.dart` and `calendar_screen.dart` are only touched for the
subtitle string; apply AGENTS.md "Fix what you touch" if the file has an allowlist entry in
`test/helpers/ui_standards_allowlist.dart` (≤ 10 lines per deviation, else list under "Standards seen,
not fixed"); never raise a ratchet.

## Scenarios

Shared fixture **F-124** (fixed clock `now = 2026-11-10 12:00 local`, `ownerUserId = 'user-1'`). Templates
via `createTemplate`: `tpl-124-iso` focus `isometric_stretching`; `tpl-124-mixed` focus null;
`tpl-124-cardio` focus `cardio_endurance`. Planned rows (day = start-of-day):

| id | day | routineTemplateId | modality | note |
|---|---|---|---|---|
| p-1 | 2026-11-12 (future) | tpl-124-iso | null | main case |
| p-2 | 2026-11-12 | tpl-124-cardio | null | same day as p-1 |
| p-3 | 2026-11-13 | tpl-124-mixed | null | no Focus |
| p-4 | 2026-11-14 | tpl-124-gone (no row) | null | orphan |
| p-5 | 2026-11-15 | null | `sports` | plain-modality plan |
| p-6 | 2026-11-03 (past) | tpl-124-iso | null | planned in the past, never started |
| p-7 | 2026-11-12 | tpl-124-iso | null | `linkedSessionId: 's-124'` (excluded) |

Expected resolved `entry.modality`: p-1 `isometric_stretching`, p-2 `cardio_endurance`, p-3 null,
p-4 null, p-5 `sports`, p-6 `isometric_stretching`, p-7 not in the grid.

### S-12401: Focus resolved for a planned routine
- Fixture: F-124, both harnesses; `CalendarState(repo, now: …)` on Nov 2026, `init()`.
- Expected: `entriesForDay(Nov 12)` has the entry for p-1 with `modality == 'isometric_stretching'`,
  `isCompleted == false`, `plannedSession.id == 'p-1'`. Red today (null).
- Edge case of: none
### S-12402: Routine with no Focus stays Free
- p-3: `modality == null`. Green today (guard).  Edge case of: S-12401
### S-12403: Orphan routine never throws
- p-4: loads, `modality == null`; day-list title for it is "Custom Routine". Green today for the title; the
  no-throw part guards the new lookup.  Edge case of: S-12401
### S-12404: Plain-modality plan unchanged
- p-5: `modality == 'sports'`. Green today (guard).  Edge case of: S-12401
### S-12405: Focus changed after planning
- Fixture: p-1 loaded as in S-12401; then `updateTemplate(tpl-124-iso, focusModality: 'cardio_endurance')`;
  `calendarState.refresh()`. Expected: p-1 → `cardio_endurance`; the p-1 row's `toMap()` unchanged
  throughout. Red today.  Edge case of: S-12401
### S-12406: Planned in the past
- p-6 (Nov 3, clock Nov 10): `modality == 'isometric_stretching'`, `isCompleted == false`. Red today.
- Edge case of: S-12401
### S-12407: Two entries on one day
- Nov 12 holds p-1 and p-2 (p-7 excluded): two entries with modalities `isometric_stretching` and
  `cardio_endurance` (order-independent); `ModalityColorUtils.colorForModality` of the two differs from
  each other. Red today.  Edge case of: S-12401
### S-12408: Nothing written, bounded template reads
- Fixture: counting Mock subclass (records `getTemplates` calls and any `updatePlannedSession`/
  `createPlannedSession`). F-124 month: exactly 1 `getTemplates` call per load, 0 planned writes, all
  planned `toMap()` identical after. A month with only p-5 (plain plan) → 0 `getTemplates` calls.
  Fails today only on "1 call" being 0, so also pinned by S-12401.  Edge case of: S-12401
### S-12409: Starting a planned routine leaves the plan untouched
- Fixture: Mock; p-1 for today; tap the entry in `DaySessionListScreen` (today). Expected: p-1 row
  `toMap()` identical before/after the tap; the new session exists. Green today and after (guard against
  124 and 122 interacting; asserts nothing about the session's modality — that is 122's S-12203).
- Edge case of: S-12401
### S-12410: Monthly breakdown unchanged
- Fixture: F-124 plus one completed free session on Nov 5 (`modality == null`). Expected
  `modalityBreakdown == {null: 1}` — planned entries are not counted. Green today and after.
- Edge case of: S-12401
### S-12411: Day-list subtitle (Q1 default)
- Fixture: Mock `testWidgets`; day Nov 12 as seen from Nov 10: p-1 and p-3 variants (separate days).
  Expected: p-1's card subtitle text is `Isometric / Stretching  ·  Planned`; p-3's is `Planned`; p-5's is
  `Sports  ·  Planned`. Red for p-1 today.  Edge case of: S-12401

## Iteration 1

### Phase 0: red tests (crew-builder-app; writes `test/**` only)
1. [ ] Record baselines in the evidence file: `flutter analyze` issue count; pass/fail of the Done Criteria suites.
2. [ ] Create `test/planned_routine_calendar_modality_test.dart`: F-124 builder, S-12401-S-12410 (plain `test()`, `harnessFactories`; counting Mock subclass for S-12408) and S-12411/S-12409 (Mock-only `testWidgets`, style of `screen_widget_test.dart` "DaySessionListScreen").
3. [ ] Run and paste the red table. Expected RED = S-12401, S-12405, S-12406, S-12407, S-12411 (p-1 line); expected GREEN = S-12402, S-12403, S-12404, S-12409, S-12410, and S-12408's "0 planned writes / plain month 0 calls" parts (its "1 call" part is red). Any other outcome is logged and explained.

**Done Criteria:** `flutter test test/planned_routine_calendar_modality_test.dart` shows exactly the split above (counts pasted); analyze ≤ baseline; invariant greps clean.
**Predicted Files:** the new test file; evidence.

### Phase 1: resolution + subtitle (crew-builder-app; ~25 production lines)
1. [ ] `lib/state/calendar/calendar_state.dart`: `CalendarEntry.fromPlannedSession(p, {routineFocus})`; `_loadMonth` fetches `getTemplates()` once when needed and passes the Focus per D-12402/D-12403; update the `modality` field doc comment (:15).
2. [ ] `lib/features/calendar/day_session_list_screen.dart` `_buildSubtitle`: per D-12405 (Q1 default). Fix-what-you-touch per UI Standards Impact.
3. [ ] `lib/data/models/models.dart` `PlannedSession.modality` doc comment (D-12407; comment only).

**Done Criteria:** `flutter test test/planned_routine_calendar_modality_test.dart test/calendar_state_month_init_test.dart test/calendar_streak_state_test.dart test/calendar_streak_screen_test.dart test/calendar_summary_screen_bugs_test.dart test/calendar_layout_responsive_test.dart test/pr6_routine_session_entry_navigation_test.dart` all green; `flutter test test/screen_widget_test.dart --plain-name "DaySessionListScreen"` green; `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green; invariant grep empty; analyze ≤ baseline. Show S-12401 red→green (cite the Phase 0 run).
**Predicted Files:** the three lib files; the test file only if a fixture needs a logged fix; plan Progress; evidence.

### Phase 2: docs (crew-docs-keeper)
1. [ ] `docs/calendar_periods.md` (13.0 KB): a planned routine entry is coloured by the routine's current Focus, resolved on each month load (a plan follows the routine; a finished session keeps its own, plan 122); no Focus → Free; subtitle per Q1; pointers S-12401, S-12405, S-12411. Replace/avoid 122's sentence (see Order).
2. [ ] `docs/my_routines.md`: one line under the planning/"Plan a routine" section pointing to the same rule.
3. [ ] Size check: `wc -c` of both docs < 53 248 bytes; `flutter test test/docs_indexing_contract_test.dart` green.

**Done Criteria:** item 3 output pasted; `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green.
**Predicted Files:** the two docs; evidence.

## Files Affected

Production: `lib/state/calendar/calendar_state.dart`, `lib/features/calendar/day_session_list_screen.dart`
(`_buildSubtitle` only), `lib/data/models/models.dart` (comment). Tests: one new file. Docs: two.
Not touched: `_tapPlanned` (122), repositories, `data_version.dart`, schema/seed, `watch/`, Stats.

## Notes

- Size: 2 phases of code+tests, ~25 production lines, one track: well inside the budget; no split needed.
- No clean-up debt: nothing here needs later removal.

## Noticed, not planned

1. Same as 122 note 1: "Mixed / Not set" may not clear a routine's Focus (`RoutineState.updateRoutineFocusModality(null)`
   with `copyWith(focusModality: null)` keeps the old value). If true, a planned "Mixed" routine would keep a
   Focus colour here too. Read from code, not run.
2. `CalendarEntry` for a planned *free* plan whose modality is chosen in the form is fine; a routine plan's
   `modality` column is always null by design — a future writer that sets both would be tolerated
   (`routineFocus ?? p.modality`).
3. `calendar_state.dart:152-153` hides a planned entry once linked; if a linked plan's session is later
   deleted the plan disappears from the grid (existing behaviour, not investigated).

## Progress
- [x] Phase 0 · [x] Phase 1 · [x] Phase 2 · [x] review

## Assumption Log
- Clock/fixture dates chosen so Nov 12 is a future day from Nov 10; the builder may shift them if the repo's
  date helpers need it, logging the change.
- `getTemplates()` returns every template including deleted-flag-free ones; builder confirms it includes
  templates not currently loaded in `RoutineState` (the day list's :531 lookup uses `routineState.routines`,
  which only holds loaded routines).

## Feedback
