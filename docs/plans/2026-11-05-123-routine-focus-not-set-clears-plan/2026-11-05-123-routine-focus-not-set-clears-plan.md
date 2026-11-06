# Feature: 123 — "Mixed / Not set" must remove a routine's Focus Modality

> Status: Phase 0 done (red tests observed failing); Phases 1-2 not started. No open owner question.
> Next handoff: crew-builder-app (Phase 1: the fix)
> Binding conventions: `docs/global_conventions.md`; `docs/documentation_standard.md` (Phase 2);
> `docs/my_routines.md`; `.github/copilot/pr-scope-budget.md`.
> Track: phone only (`lib/`), small. Lands BEFORE or WITH plan 122's back-fill (see Ordering).
> Evidence → `…-plan.evidence.md`; review → `…-plan.review.md`.

## Overview

Bug (now proved, not just read): in the routine editor, picking **Mixed / Not set** on a routine that
has a Focus leaves the Focus in place. Save and reopen: the old Focus is still there; routine workouts
started from it carry it.

Root cause: `RoutineState.updateRoutineFocusModality(String?)` (`lib/state/routine/routine_state.dart:213`)
calls `WorkoutTemplate.copyWith(focusModality: modality)` (`lib/data/models/models.dart:723`), which
writes `focusModality ?? this.focusModality`, so `null` means "keep". An existing test pins the bug as a
"limitation": `test/state_test.dart:306-319` ("…with null preserves prior value"). That test must flip.

Both repositories are innocent: Hive and Mock `createTemplate`/`updateTemplate` write the whole template
(`hive_workout_repository.dart:2062`, `mock_workout_repository.dart:1271`), `toMap` writes `focus_modality`
as-is, and `scripts/sqlite_schema.sql:464` has `focus_modality TEXT` (nullable). The SQL contract needs no change.

Other nullable template fields: `description`, `note`, `primaryDisciplineId`, `ownerUserId` share the
same `??` trap in `copyWith`, but the editor cannot clear any of them (description is a non-null `String`
param, so "" is stored as ""; note/discipline/owner have no editor call). Not fixed here; the fix must
not make them worse (see D-2). Dirty check (`_matchesBaseline`, :1167) is correct in itself; it only
looked wrong because the in-memory template never became null — S-12308 proves it follows once the fix lands.

## What the owner should know (plain language)

1. After the fix, choosing Mixed / Not set on a routine, saving and reopening shows Mixed, and workouts
   started from it carry no Focus. Leaving the editor with that change unsaved asks "unsaved changes" like any other edit.
2. **Routines you already saved are left as they are.** The app cannot tell that you meant Mixed for a
   routine that still shows a Focus. If one shows a Focus you did not want, open it, pick Mixed, save.
3. Picking another Focus, or no change, behaves as before.

## Decisions

- **D-1** (technical, mine): add a `clearFocusModality` flag to `WorkoutTemplate.copyWith` (default
  `false`; when `true` the result's Focus is `null`, overriding `focusModality`). Smallest change,
  no call-site churn, no sentinel type. `updateRoutineFocusModality(null)` passes the flag.
- **D-2**: no flags for `note`/`description`/`primaryDisciplineId`/`ownerUserId` now: no editor path
  clears them; add one when a screen needs it (YAGNI). Recorded as a known trap in the `copyWith` doc comment.
- **D-3** (default, owner-reversible): already-saved routines are NOT migrated. No data migration,
  no `data_version` bump, no catalog bump.
- **D-4**: built-in demo routines are unaffected (the catalog refresh compares Focus at
  `catalog_refresh_service.dart:421` and respects the user-edit tombstone); a user clearing Focus on a demo
  routine is a user edit and stays authoritative.

## Ordering with plan 122

Plan 122's one-off back-fill copies each routine's CURRENT Focus onto its past sessions. With this bug,
a routine the owner meant as Mixed still holds its old Focus, so the back-fill would stamp that old
Focus on past workouts, and the stamp cannot be undone from the routine afterwards. So: **123 lands
before 122's back-fill step ships, or in the same release.** 123 has no dependency on 122. Even then the
back-fill cannot rescue routines the owner already tried to set to Mixed and saved (D-3); 122's note to
the owner should say "check routines you meant to be Mixed before updating" (122 owns that wording; not edited here).

## Scenarios (each on Mock AND Hive; `test/routine_focus_not_set_test.dart`)

| ID | Fixture | Expected | Phase 0 result |
|---|---|---|---|
| S-12301 | Focus → Mixed, save, reopen | reopened Focus is null | **FAIL** (still `resistance_lifting`) |
| S-12302 | Mixed → Focus | saved Focus | pass (regression guard) |
| S-12303 | Focus → other Focus | saved the other Focus | pass (guard) |
| S-12304 | unchanged Focus / unchanged Mixed, other edit saved | both unchanged | pass (guard) |
| S-12305 | Focus → Mixed with exercises present | Focus null, same efforts | **FAIL** |
| S-12306 | routine created outside the editor (seeded/imported) with a Focus → Mixed | Focus null | **FAIL** |
| S-12307 | Focus → Mixed picked, then discarded unsaved | stored and reopened Focus unchanged | pass (guard) |
| S-12308 | Focus → Mixed is an unsaved change; back to the same Focus is not | `hasUnsavedChanges` true then false | **FAIL** |

Also: flip `test/state_test.dart:306-319` to expect `null`; add a model-level case for `copyWith`
(`clearFocusModality: true` → null; default keeps; `focusModality:` set still sets).

## Phase 0 — red tests (DONE)

`test/routine_focus_not_set_test.dart` written. Observed run (`flutter test test/routine_focus_not_set_test.dart`,
2026-11-05, before any source change): **8 passed, 8 failed** — failures S-12301, S-12305, S-12306,
S-12308 on Mock and on Hive, e.g. `Expected: null  Actual: 'resistance_lifting'`. (My first Hive S-12307
errored from a test mistake — reading through the pre-restart repository — and was corrected; it now passes.)
Final transcript goes in the evidence file when Phase 1 runs.

## Phase 1 — the fix (not started)

- `models.dart` `WorkoutTemplate.copyWith`: add `bool clearFocusModality = false`; `focusModality: clearFocusModality ? null : (focusModality ?? this.focusModality)`.
- `routine_state.dart:213`: pass `clearFocusModality: modality == null`.
- Flip `state_test.dart` case; add the model case.
- Done when: new file 16/16 green, `state_test.dart` green, `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green, invariant grep empty; the 4 failing scenarios re-shown failing with the fix stashed.

## Phase 2 — docs (not started)

`docs/my_routines.md` Focus section: say Mixed = `null` and that choosing it removes an existing Focus;
add the "already-saved routines are left as they are" line. `docs/data_models.md`: note the `copyWith` flag.
`docs/db_integration.md`/SQL: no change (stated, not edited).

## Out of scope / noticed

- Flags for the other nullable template fields (D-2).
- Reading side of the stale Focus on past sessions belongs to plan 122.

## Progress

- [x] Phase 0 red tests observed failing
- [ ] Phase 1 fix
- [ ] Phase 2 docs
