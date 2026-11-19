# Review: plan 124 · Phases 0–2 · base (HEAD 558cfb40) .. working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 0 · minor 4 · tests: full `flutter test` run this review: 6833 passed, 2 skipped, 22 failed (all 22 in `test/wrist_pause_resume_adoption_test.dart` — watch/plan-126 working-tree changes by another session, not among this diff's files; no plan-124 or calendar/ui-standards/docs-contract test failed).
Diff vs Predicted Files: conforms — exactly the six named paths changed (`lib/state/calendar/calendar_state.dart`, `lib/features/calendar/day_session_list_screen.dart`, `lib/data/models/models.dart` comment, `docs/calendar_periods.md`, `docs/my_routines.md`, new `test/planned_routine_calendar_modality_test.dart`); nothing outside. Missing predicted deliverables: the evidence file (`…-124-…-plan.evidence.md` — verified absent by directory listing) and the plan's Progress checkboxes (still unchecked); both listed as Minor 4.

## Findings
1. [Blocker] docs/calendar_periods.md:27 — "A finished session keeps the Focus it was started with." is a doc claim with no code behind it in this tree. Plan 122 has not landed (git-log HEAD is plan 120; `_tapPlanned` at `lib/features/calendar/day_session_list_screen.dart:292` still passes `ps.modality`, which is null for a routine plan, and `lib/features/routine/my_routines_screen.dart:196` starts routines with `modality: null`; `session_summary_service.dart:356` writes a template, not a session). A maintainer following the doc expects a finished routine session dot in the Focus colour; today it renders Free Training. The sentence names no test. Fix (smallest): qualify it — "once plan 122's session stamp lands, a finished session keeps the Focus it was started with (S-12203)"; or drop the clause now and let 122's Phase 4 write it. Guard: the sentence must name an existing test or be marked as 122's.
2. [Minor] `test/planned_routine_calendar_modality_test.dart` (S-12403 test, ~line 209) — the plan's S-12403 also pins the orphan's day-list title "Custom Routine"; the test asserts only `isCompleted`/`modality` at state level, so the title branch (`day_session_list_screen.dart:533-537`) has no coverage in this change. Fix: one Mock `testWidgets` on day Nov 14 asserting `find.text('Custom Routine')`.
3. [Minor] same file, S-12407 test — the plan names p-7 (linked, `linkedSessionId: 's-124'`) as excluded from the grid, but the test only filters ids `{'p-1','p-2'}`, so a leak of p-7 into `entriesForDay` would still pass. Fix: add `expect(nov12.any((e) => e.plannedSession?.id == 'p-7'), isFalse)`.
4. [Minor] Missing predicted deliverables: `2026-11-05-124-…-plan.evidence.md` does not exist (Phase 0 baseline recordings, red/green tables, Phase 2 size check output) and the plan's Progress checkboxes are unchecked. Fix: lead/governor to create the evidence file and tick the plan.

## Standards, checks
- No new allowlist entries in `test/helpers/ui_standards_allowlist.dart` for any touched file (grep: no `day_session_list|calendar_state|models` entry); no ratchet numerals in the diff; `_buildSubtitle` adds no widget, no `shape:`, no colour literal — standards clean.
- Assumption Log rulings:
  - Entry 1 (fixture dates) — **ratify**: the test uses the planned dates verbatim (`_clock124`, `_day124`).
  - Entry 2 (`getTemplates()` returns templates not loaded into `RoutineState`) — **ratify**: S-12401 passes on both harnesses with templates created only via `repo.createTemplate` and never loaded into `RoutineState`.
- Mutation kills reported by the lead (routineFocus ignored, empty-string focus, any-routine guard, subtitle branch) are taken from the brief as established facts; no prove-red verdict was attached to the brief, so they are unproven by this review (the tests as written do assert the right pipe for each: S-12401/S-12405 (ignore), S-12402-empty (empty string), S-12408 plain-month 0-calls (any-routine guard), S-12411 p-1 and p-3 (subtitle branch)).

## Questions answered
- Q1 (D-12401..12406): match. Resolution is display-time only in `CalendarState._loadMonth` (`calendar_state.dart:167-190`); `_loadMonth` awaits `getTemplates()` once, only when some unlinked planned row has a `routineTemplateId`; the map drops null/empty focuses (D-12403). No `PlannedSession` write anywhere on this path (`getTemplates` appears at :172 only; nothing else added to repository calls). Freshness per D-12406 via normal month loads / `refresh()`.
- Q2 (other callers of `CalendarEntry.fromPlannedSession`): only two besides the new one — `lib/state/calendar/calendar_state.dart:181` (the new path) and `test/ui_standards_widget_test.dart:72`, which builds a plain-modality plan (`routineTemplateId` unset, `modality` set, no `routineFocus`) and keeps today's behaviour. No other place in `lib/` or `test/` builds planned entries (grep `CalendarEntry._(` direct constructions: only inside the factory). The only direct readers of a planned row's modality are `calendar_state.dart:284` (mark-planned-done copy) and `day_session_list_screen.dart:292` (`_tapPlanned`, plan 122's, untouched) — neither changes.
- Q3 (`_buildSubtitle`): cannot affect a completed or in-progress routine session. The new branch requires `ps?.routineTemplateId != null`, and `entry.plannedSession` is non-null only for `fromPlannedSession` entries — completed sessions come from `CalendarEntry.fromSession` with `plannedSession` null, so a finished routine session keeps the old `'$modalityLabel · $stateLabel'` line; an in-progress session returns `'… · In Progress'` at the earlier branch (`:552`) before the new branch is reached. Verified by reading `_buildSubtitle` (:532-563) and the two factories (:36-56).
- Q4 (docs vs code): `calendar_periods.md` agrees with the code (current-focus resolution per load, no-Focus/orphan → Free, responsibilities bullet matches the guarded single read). One false sentence on finished sessions — Finding 1. `my_routines.md` sentence is true; placement under "Deleting a Routine" instead of a planning section — Finding 5 note below.
5. [Minor] docs/my_routines.md:51 — the plan's Phase 2 said the line goes under the planning/"Plan a routine" section, which does not exist in `docs/my_routines.md` (verified headings: Overview / Editing and Deleting / Technical Architecture / UI Architecture / Home Screen Integration / Key Design Decisions / Code References / Related Documentation); the sentence landed under "Deleting a Routine" instead, so a reader looking for scheduling behaviour will not find it. Fix: move to the Overview or leave, owned by the docs keeper.
- Q5 (tests that pass regardless of the fix): none problematic. Red-by-design are S-12401, S-12405, S-12406, S-12407, S-12408's "1 call", S-12411 p-1 — each asserts a value that is null/absent before the change (`p.modality` is null for every routine plan and the old subtitle is plain "Planned"), so each fails on HEAD. The remaining tests are declared guards in the plan and assert invariants that survive either way. Two coverage gaps exist but both are additive (Findings 2, 3), not guards proving nothing.

## Docs delta
Plan has no `## Docs delta` table. The inline Phase 2 edits were applied: `calendar_periods.md` (Session Indicators + CalendarState responsibilities) -> applied; `my_routines.md` (colour pointer) -> applied (see Finding 5). No other doc edit found that neither Phase 2 nor the table names (`docs/README.md`, `docs/state_management*` changes in the tree belong to the watch session, not read as 124's).

## Assumption Log rulings
See "Standards, checks" above (both ratify; log is non-empty).

## Scenario coverage
- S-12401 -> test/planned_routine_calendar_modality_test.dart · "S-12401: a planned routine resolves its Focus" (both harnesses) | covered
- S-12402 -> "a routine with no Focus stays Free" + "an empty-string Focus counts as no Focus" | covered
- S-12403 -> "an orphan routine id never throws, stays Free" | covered state-level only; title "Custom Routine" MISSING (Finding 2)
- S-12404 -> "a plain-modality plan keeps its own modality" | covered
- S-12405 -> "a Focus edit after planning changes the plan colour" (asserts row `toMap()` unchanged) | covered
- S-12406 -> "a planned routine in the past still resolves" | covered
- S-12407 -> "two routine plans on one day resolve apart" | covered, p-7 exclusion MISSING (Finding 3)
- S-12408 -> three tests (writes-only, 1 read per load, 0 reads for a plain month) | covered
- S-12409 -> "tapping a planned routine leaves the plan row untouched" (Mock testWidgets) | covered
- S-12410 -> "planned entries stay out of the monthly breakdown" ({null: 1}) | covered
- S-12411 -> "the card subtitle names the Focus" / "keeps just Planned" / "plain-modality card keeps its label" | covered
