# Feature: 122 — Routine sessions carry the routine's Focus Modality (+ one-off back-fill)

> Status: Iteration 1 ready; amended 2026-11-05 — owner answered Q1 with ALTERNATIVE A (no open questions)
> Next handoff: crew-builder-app (Phase 0: red tests, now including the add-exercise tests)
> Binding conventions: `docs/global_conventions.md`; `docs/documentation_standard.md` (Phase 4);
> `docs/my_routines.md`, `docs/calendar_periods.md`, `docs/db_integration.md` (data-migration section),
> `.github/copilot/pr-scope-budget.md`. Pattern precedent: plan 117
> (`docs/plans/2026-11-04-117-retire-orphan-template-rows-plan/`).
> Track: phone only (`lib/`). Siblings 120, 121a, 121b are planned in parallel; none of their scope is here.
> Evidence → `2026-11-05-122-routine-session-modality-plan.evidence.md`; review → `…plan.review.md`.

## Overview

A workout started from a routine is saved with no modality, so the calendar calls it "Free Training"
even when the routine's Focus is, for example, Isometric / Stretching. Root cause (verified):
`lib/features/routine/my_routines_screen.dart` `_startRoutine` (:196-202) and
`lib/features/calendar/day_session_list_screen.dart` `_tapPlanned` (:280-286) both call
`createNewSession(modality: null, intent: 'routine', routineTemplateId: …)`; the watch-adoption path
`lib/state/watch/watch_session_adoption_bridge.dart` `_adopt` (:808-823) writes the session with no
modality either. `WorkoutTemplate.focusModality` (`lib/data/models/models.dart:668`) never reaches
`TrainingSession.modality`.

The session DOES record its routine: `TrainingSession.routineTemplateId` (`models.dart:194`, map key
`routine_template_id` :232/:251), persisted by Hive (`updateSession`/`createSession` write `toMap()`,
`hive_workout_repository.dart:1045-1051`) and the Mock (`mock_workout_repository.dart:491`), and in the
contract `scripts/sqlite_schema.sql:191` (`app_training_session.routine_template_id TEXT`). Deleting a
routine keeps the id on its sessions (`test/pr6_routine_session_entry_navigation_test.dart`, S-002). No
blocking question.

This plan (1) stamps the routine's Focus on every new phone-side routine session and (2) back-fills
past routine sessions once, through the existing data-migration sequence, as an isolated step marked
for retirement after launch.

## What the owner should know (plain language)

1. **The calendar will change for past workouts.** After the update, past routine workouts whose
   routine has a Focus show that Focus's colour and name in the calendar, the day list and the month's
   breakdown chips, instead of "Free Training". Routines with no Focus stay "Free Training".
2. **The back-fill uses each routine's Focus as it is today**, not as it was when the workout was
   done. If you changed a routine's Focus since, its old workouts take the new one. A workout whose
   routine was deleted cannot be fixed and stays "Free Training".
3. **The Stats screen does not shift.** Stats count what you actually logged (sets, holds, timed work,
   rounds), never the session's label (`grep -rn "\.modality\b" lib/core/services/stats_progress_service.dart lib/core/services/signals lib/features/stats lib/state/stats lib/core/models` → 0 hits).
4. **Apple Health: new routine workouts get a real type.** When the phone writes a finished workout to
   Health, it picks the type from the session's modality (`lib/core/services/health_modality_mapper.dart`).
   Today a routine workout goes in as "Other"; after this change a Stretching-focused routine goes in as
   Flexibility, Resistance as Strength, Cardio as Cardio, Sports as Sport. An all-yoga workout still goes
   in as Yoga. Workouts already sent to Health are NOT resent, so past ones stay "Other" there.
5. **The watch is not affected.** The phone never sends a session's modality to the watch (only the
   watch sends one to the phone: `grep -rn "'modality'" lib/core/services lib/state` → only
   `watch_session_importer.dart:2213`, inbound). A routine started on the wrist still has no Focus on the
   wrist (its routine list has no field for it), but once the phone takes that workout over it is saved
   with the Focus like any phone-started routine.
6. **Exercises keep their own tracking.** A routine stores each exercise's tracking kind, so a squat in
   a Stretching routine is still logged as sets and counted as strength. The workout is just *labelled*
   Stretching — mixed content under the routine's declared focus.
7. **Adding an exercise during a routine workout does not change (your answer to Q1: A).** The app keeps
   asking "what kind of exercise is this?" and shows the full exercise list, exactly as today, for every
   routine workout, with or without a Focus. The Focus only labels and colours the workout (and sets its
   Health type).
8. **Risk worth fixing first (not in this plan):** picking "Mixed / Not set" for a routine that already
   has a Focus appears not to remove the Focus (read from code, not run — see Noticed, item 1). If that
   is true, those routines' workouts get the old Focus.

## Questions

**Q1 — RESOLVED: owner chose A (2026-11-05).** Adding an exercise in the middle of a routine workout that
carries a Focus keeps asking the kind of exercise (today's modality prompt) and does not use the Focus's
kind or a "Recommended" list. The session's modality is only a label / colour / Health type for routine
sessions and must not change the add-exercise flow. This reverses the earlier default (B), D-12205 and
S-12206. No open questions remain; the one detail the owner did not state is logged as D-12213 (default
taken, vetoable).

## Resolved Decisions (Ledger)

- **D-12201 Start rule.** A routine session created on the phone gets
  `modality = template.focusModality` of the template it is built from, copied verbatim, in the same
  `createSession` write (null stays null). In scope, exactly three paths:
  (a) `my_routines_screen.dart` `_startRoutine` → `manifest.template.focusModality`;
  (b) `day_session_list_screen.dart` `_tapPlanned`, routine branch → `manifest.template.focusModality`;
  (c) `watch_session_adoption_bridge.dart` `_adopt` → `routine?.template.focusModality` (null when no
  routine matched). **Derived, vetoable:** (c) reads owner decision 1 ("a new routine session takes the
  Focus") as covering a wrist-started routine the phone adopts. Out of scope: the wrist's own session
  record (Swift, `WatchStartPaths.swift:557-585`, `routines_down` has no focus field) and the watch
  importer (`watch_session_importer.dart:579-592`, which never links a routine). The non-routine branch
  of `_tapPlanned` (:292, `modality: ps.modality`) and all other `createNewSession` callers
  (home tiles, Free Training, empty-session fallbacks) are unchanged.
- **D-12202 Snapshot.** A session's modality is fixed when it is written. Editing a routine's Focus
  later never rewrites any session (new or back-filled); deleting a routine leaves its sessions as they
  are (existing PR 6 S-002 rule).
- **D-12203 Per-exercise kinds untouched.** `populateSessionFromManifest`
  (`lib/state/workout/session_core_io.dart:305-350`) keeps passing each template effort's own
  `effortKind` as the override (`TemplateEffort.effortKind` is non-null, `models.dart:802`), so the
  Focus never changes a routine exercise's kind. Analytics stay keyed on effort kind
  (`docs/global_conventions.md`, "Effort-kind drives analytics").
- **D-12204 Home tiles.** While a routine session is active, only the Routines tile is active; a
  modality tile is active only for a non-routine session whose modality equals the tile's
  (`home_screen.dart:513-521`: the modality branch gains `!isRoutineSession`). Tapping a modality tile
  during a routine session behaves as today (asks to discard and start new). Rests on
  `docs/my_routines.md` Decision 3 ("rather than highlighting a modality tile"). Without this, stamping
  would light two tiles and make the Isometric tile resume the routine.
- **D-12205 Mid-session add (Q1 = A; supersedes the earlier B default).** In a routine session
  (`session.intent == 'routine'`) adding an exercise behaves exactly as it does today, whatever the
  session's modality: the modality prompt (`ModalityPickerDialog`) is shown and its answer becomes the
  `effortKindOverride`. Cause (verified): both add-exercise screens decide to prompt from
  `session.modality == null` alone — `workout_session_screen.dart` `_addExercise` (:1624-1675, prompt at
  :1643-1666) and `session_overview_screen.dart` `_addExercise` (:73-110, prompt at :86-101) — so a
  stamped routine session would silently skip the prompt, and `session_core_entry.dart:24-31` would take
  `ModalityConfig.forModality(session.modality).effortKind` instead. Fix: in both screens, a local
  `askKind = session.modality == null || session.intent == 'routine'` replaces the null test (the workout
  screen's rolling `preferredModality` branch is unchanged and unreachable for a routine session, since
  routine sessions are not tile-started). Discriminator = `intent == 'routine'`, the same
  field D-12204 and `home_screen.dart:506-507` already use; `routineTemplateId != null` is NOT used (the
  list view :434 uses it for a different purpose, and S-g-style rows carry a link without intent).
  Non-routine modality sessions (home tiles) keep skipping the prompt. `addExerciseToSession` /
  `session_core_entry.dart` are NOT changed: an explicit override already wins.
- **D-12213 Picker contents in a routine session (Q1 = A, owner did not specify; default, vetoable).**
  The exercise picker is opened exactly as today for a routine workout: `sessionModality: null`, so it
  shows the full list, unsorted, with NO "Recommended" section and no ranking by the Focus
  (`exercise_picker_screen.dart` :150/:326 key off `sessionModality == null`; ranking :116). Reason:
  the app is about to ask what kind the exercise is, so ranking by the Focus first would pre-judge that
  answer. Implemented by passing `askKind ? null : modality` as `sessionModality` in both screens. The
  routine editor's own "Recommended for the Focus" behaviour (`routine_setup_screen.dart`) is unchanged.
  If the owner wants Recommended shown while still asking, it is a one-line change (pass the Focus
  through) — ask only if they raise it. `session_summary_screen.dart:555-640` ("Save as routine" template
  builder, not a mid-session add) is NOT changed: it now follows the Focus like the routine editor
  does (already listed in D-12211).
- **D-12214 Sequencing.** (a) The add-exercise remediation (Phase 1b) must land BEFORE or WITH the first
  stamping change (Phase 1); inside this PR it runs first. It is harmless on its own (an `intent ==
  'routine'` test is true for today's null-modality routine sessions too). (b) **Plan 123** (routine
  editor: choosing Mixed / Not set must not leave an existing Focus — "Noticed" item 1) must land BEFORE
  or WITH Phase 2's back-fill, so cleared Focuses are not stamped onto past sessions; if 123 is not
  committed when Phase 2 starts, stop and ask the governor. (c) **Plan 124** (planned, not-yet-started
  routine entries in the calendar — "Noticed" item 2) is separate and not a prerequisite or part of this
  plan; D-12206 still never touches planned rows.
- **D-12206 Back-fill selection rule.** For every `TrainingSession` from `getAllSessions()`:
  stamp it iff `intent == 'routine'` AND `modality == null` AND `routineTemplateId` is non-null and
  non-empty AND `getTemplateById(routineTemplateId)` returns a template AND that template's
  `focusModality` is non-null and non-empty. The write is
  `updateSession(TrainingSession.fromMap({...s.toMap(), 'modality': focus}))` — every other field,
  including `updated_at_ms` and `ended_at_ms`, is unchanged. In-progress sessions (`endedAtMs == null`)
  are included (migration runs inside `repository.initialize()`, `lib/main.dart:255`, before any state
  loads a session). `PlannedSession` rows are never read or written. A missing template is skipped
  silently (no throw, no log noise). The Focus value is copied verbatim (same rule as D-12201).
- **D-12207 Delivery and identity.** One core service, `RoutineSessionModalityBackfill`
  (`lib/core/services/routine_session_modality_backfill.dart`, depends on `WorkoutRepository` only, no
  new repository method), run by a new data-migration step named `backfillRoutineSessionModality`,
  appended to BOTH `HiveWorkoutRepository._dataMigrationSteps()` (as `_MethodStep`) and
  `MockWorkoutRepository._dataMigrationSteps()` (as `_MockMigrationStep`), with
  `currentDataVersion = 18` (`lib/core/constants/data_version.dart`). If a sibling plan has already
  taken 18 when Phase 2 starts, take the next free integer and log it; tests find the step by NAME.
  "Its own version flag" = its own `data_version` step; no new meta-box key.
- **D-12208 Interruption and idempotency.** Rows are written one at a time; a throw propagates;
  `DataMigrationService` does not advance `data_version` past the step (`data_migration_service.dart`
  run loop), so the next launch re-runs it; rows already stamped no longer match D-12206 and are
  skipped. A second run performs zero `updateSession` calls.
- **D-12209 Removability.** The service's doc comment, the step rows in both repositories and the
  `docs/db_integration.md` section each carry the label **"ONE-OFF (plan 122) — retire after launch"**.
  Retirement procedure (documented, not performed): replace the step's run body with a no-op keeping
  its version and name, delete the service and its test file, update the docs; never renumber or remove
  a version (a device below it would stop short of `currentDataVersion`).
- **D-12210 Health consequence accepted.** New focused routine sessions are written to the phone's
  health store with the Focus mapping (`mapModalityToActivityKind`); the all-Yoga rule
  (`health_sync_service.dart:111-135`) still wins. Back-filled sessions are not re-sent
  (`onSessionCompleted` is the only writer, `session_core_lifecycle.dart:59`, guarded by the written
  ledger). **Flagged to owner, vetoable.**
- **D-12211 Other visible consequences accepted** (all read `session.modality`, all intended):
  calendar colour/label/subtitle (`day_session_list_screen.dart:429/542/548`, `calendar_screen.dart:600`),
  month breakdown (`calendar_state.dart:307-317`), workout header fallback name
  (`workout_session_list_view.dart:1008`, only when the title is empty — routine sessions have one),
  round noun "Periods" for a Sports focus (`ModalityDisplay.roundNoun`, list view :102, detail view :821,
  summary group metrics), the effort-rating sheet's name, and Summary → "Save as routine": default name
  and the new routine's Focus now follow the session (`session_summary_screen.dart:551/713-720`).
- **D-12212 Test style.** Back-fill scenarios: plain `test()` over `harnessFactories`
  (`test/helpers/repository_harness.dart`). Start-path, tile and day-list scenarios: Mock-only
  `testWidgets` (persisting taps are Mock-only). Adoption: the existing two-harness
  `test/watch_routine_adoption_test.dart` style. Every new test names its S-id.

## Feature Invariants

- A session's modality, once written, is never changed by a later routine edit (D-12202).
- A routine session (`intent == 'routine'`) always asks the exercise kind when adding an exercise (D-12205).
- The back-fill writes only `modality`, only on rows matching D-12206, and never touches planned rows.
- Mock and Hive run the same back-fill code and expose identical step sequences (name and version).
- `lib/state` and `lib/features` depend on `WorkoutRepository` only (AGENTS.md invariant grep).

## Requirements → Acceptance Criteria

- AC-1 New phone routine sessions carry the Focus (S-12201, S-12202, S-12203, S-12204).
- AC-2 Exercise kinds inside a routine are unchanged (S-12201).
- AC-3 Only the Routines tile lights for a routine session (S-12205).
- AC-3b Adding an exercise in any routine session still asks the kind and lists unranked (S-12206, S-12217-S-12219).
- AC-4 Past routine sessions are back-filled exactly per D-12206, idempotently, surviving interruption
  (S-12210 … S-12216).
- AC-5 Calendar breakdown and day list reflect the back-fill (S-12207); Health type pinned (S-12208).
- AC-6 Docs updated, all within the size band (Phase 4).

## Existing-Functionality Impact

| Touched surface | Readers (grep) | Effect | Guarded by |
|---|---|---|---|
| `TrainingSession.modality` on routine sessions | `grep -rn "\.modality\b" lib` (≈80 hits; session readers listed in D-12205/D-12210/D-12211) | label/colour/Health follow the Focus; add-exercise does NOT (D-12205) | D-12204, D-12205, D-12210, D-12211, S-12205-S-12208 |
| Add-exercise flow (both screens) | `grep -rn "ModalityPickerDialog" lib` → `workout_session_screen.dart:1656`, `session_overview_screen.dart:91` (+ routine editor, unrelated) | must keep prompting for routine sessions despite a stamped modality; picker gets `sessionModality: null` | D-12205, D-12213, S-12206, S-12217-S-12219; existing `test/pr6_routine_session_entry_navigation_test.dart`, `test/screen_widget_test.dart` |
| Home tile active rule | `home_screen.dart:505-521` | would light 2 tiles | D-12204, S-12205; existing `test/interaction_flow_test.dart` (cold-start tile tests) |
| `createNewSession` routine callers | `grep -rn "createNewSession(" lib` → home :764/:899, day list :280/:292, my routines :196, session screens :582/:63, `session_core_io.dart:133` | only the two routine calls change | D-12201, S-12201-S-12203 |
| Watch adoption | `watch_session_adoption_bridge.dart:808-823`; test `watch_routine_adoption_test.dart:609-613` asserts null for a NULL-focus template (still true; reason text updated) | adopted focused routine stamped | S-12204 |
| Stats / signals / periods | `grep -rn "\.modality\b" lib/core/services/stats_progress_service.dart lib/core/services/signals lib/features/stats lib/state/stats lib/core/models` → 0 | unaffected | — |
| Watch client | `grep -rn "'modality'" lib/core/services lib/state` → importer only (inbound) | unaffected | — |
| Data-migration sequence | `test/data_migration_test.dart` (:547-571, ~:610-630, ~:690-705, :739-746 pin 17 / last step), `test/retire_orphan_template_rows_test.dart:455-477` (pins 17) | pins move to the new last step | S-12214, Phase 2 item 4 |
| `PlannedSession` (routine mode stores `modality: null`, `day_session_list_screen.dart:922`) | calendar entries | untouched by design | S-12210 (p-1, p-2) |
| Fresh install | `grep -n "TrainingSession(" lib/mock/seed_data.dart` → 1 non-routine session | step is a no-op | S-12215 |

## UI Standards Impact

No new UI. `lib/features/home/home_screen.dart` carries 3 entries in `colorsBlackRatchet`
(`test/helpers/ui_standards_allowlist.dart:137`): apply the AGENTS.md "Fix what you touch" rule
(fix when ≤ 10 changed lines per deviation, else list under "Standards seen, not fixed"); never raise
the ratchet.

## Scenarios

Shared fixture **F-122** (fixed clock `_atMs = 1700000000000`, `ownerUserId = LoggedEntryRows.ownerUserId`,
day = 86 400 000 ms). Templates (created with `createTemplate` + segment + efforts):
- `tpl-122-iso` "Evening Stretch", `focusModality: 'isometric_stretching'`; segment `tseg-122-iso`;
  efforts `teff-122-hold` (a catalog exercise with the `hold` capability, `effortKind: 'drill'`) and
  `teff-122-squat` (a catalog exercise with `reps`, `effortKind: 'set'`, 3 targets → 3 sets).
- `tpl-122-mixed` "Mixed Day", `focusModality: null`; one `set` effort.
- `tpl-122-cardio` "Easy Run", `focusModality: 'cardio_endurance'`; one `timed` effort.
Sessions (all `title` = template name or null as listed):

| id | intent | routineTemplateId | modality | endedAtMs | after back-fill |
|---|---|---|---|---|---|
| s-a | routine | tpl-122-iso | null | _atMs+1h | `isometric_stretching` |
| s-b | routine | tpl-122-mixed | null | set | null |
| s-c | routine | tpl-122-deleted (no row) | null | set | null, no throw |
| s-d | routine | tpl-122-iso | `resistance_lifting` | set | `resistance_lifting` |
| s-e | null | null | null | set (free session) | null |
| s-f | routine | tpl-122-iso | null | **null** (in progress) | `isometric_stretching` |
| s-g | null | tpl-122-iso | null | set (link without intent) | null |
| s-h | routine | null | null | set | null |
| s-i | routine | tpl-122-cardio | null | set | `cardio_endurance` |

Planned: `p-1` (routine `tpl-122-iso`, `modality: null`, not completed, today+1 day); `p-2`
(routine `tpl-122-iso`, completed, `linkedSessionId: 's-a'`). Both byte-identical (`toMap()`) after.
Changed rows: exactly {s-a, s-f, s-i} (3); for each, `toMap()` equals the before-map with only
`'modality'` replaced.

### S-12201: My Routines start, focused routine
- Fixture: Mock; `tpl-122-iso` only; no active session.
- Trigger: tap `Key('routine-card-start')` on "Evening Stretch".
- Expected: one new session; `modality == 'isometric_stretching'`, `intent == 'routine'`,
  `routineTemplateId == 'tpl-122-iso'`, `title == 'Evening Stretch'`; its efforts' kinds are
  `['drill', 'set']` in template order (D-12203). Red today (modality null).
- Edge case of: none
### S-12202: My Routines start, no-focus routine
- Fixture: Mock; `tpl-122-mixed` only. Trigger: start it. Expected: `modality == null`. Green today (guard).
- Edge case of: S-12201
### S-12203: Calendar planned-routine start
- Fixture: Mock; `tpl-122-iso`; `p-1` scheduled today. Trigger: tap the planned entry in
  `DaySessionListScreen` (today). Expected: new session `modality == 'isometric_stretching'`;
  `p-1` row unchanged. Red today.
- Edge case of: S-12201
### S-12204: Watch-adopted routine
- Fixture: both harnesses; the file's existing `_phone`/`_snapshot` rig with its template given
  `focusModality: 'resistance_lifting'` (new test; S-3640 keeps its null-focus template and its null
  assertion, reason text updated to "a no-focus routine's session carries no modality").
- Expected: adopted session `modality == 'resistance_lifting'`. Red today.
- Edge case of: S-12201
### S-12205: Only the Routines tile is active
- Fixture: Mock; the `buildHomeWithLoadedSession`-style rig of `test/interaction_flow_test.dart`, with
  the loaded session `intent: 'routine'`, `routineTemplateId: 'tpl-122-iso'`,
  `modality: 'isometric_stretching'`, `endedAtMs: null`.
- Expected: exactly one active `EnergyTile`, title `'Routines'` (not `'Isometric'`). Green today; Phase 1
  records it RED after the stamp and before the tile change, then green.
- Edge case of: none
### S-12206: Mid-session add in a focused routine still asks the kind (D-12205; reversed by Q1 = A)
- Fixture: Mock; `WorkoutSessionScreen` (Mock-only `testWidgets`) over a session created with
  `modality: 'isometric_stretching'`, `intent: 'routine'`, `routineTemplateId: 'tpl-122-iso'`.
- Trigger: tap add exercise, pick a `reps` catalog exercise in the picker.
- Expected: `ModalityPickerDialog` is shown; answering "Resistance" gives the new effort
  `effortKind == 'set'`; answering "Isometric / Stretching" gives `'drill'`. The old B expectation
  (`'drill'` with no dialog) must NOT hold. Red today: the fixture is built already stamped (direct `createNewSession(modality: …, intent: 'routine')`), and the current code skips the dialog for it. Green after Phase 1b.
### S-12207: Calendar after back-fill
- Fixture: both harnesses; F-122 rows s-a, s-b only, both on day D; data version staged at 17.
- Trigger: run the step; `CalendarState(repo, now: D)` loads D's month.
- Expected: `modalityBreakdown == {'isometric_stretching': 1, null: 1}` (before: `{null: 2}`). Red today.
- Edge case of: S-12210
### S-12208: Health type for a focused routine session
- Fixture: Mock; the `test/health_yoga_kind_test.dart` rig; a completed session `intent: 'routine'`,
  `modality: 'cardio_endurance'`, one effort on a non-yoga exercise; a second identical session with
  `modality: null`. Expected: first written as `HealthActivityKind.cardio`, second as `.other`. Pin
  (documents D-12210); green today.
### S-12210: Back-fill selection on the full fixture
- Fixture: F-122 (all 9 sessions, 3 templates, p-1, p-2); both harnesses.
- Trigger: `dataMigrationStepsForTest().firstWhere((s) => s.name == 'backfillRoutineSessionModality').run()`.
- Expected: exactly the 3 changes in the table; all other 6 sessions and both planned rows
  `toMap()`-identical. Red today (no such step: `StateError`).
### S-12211: Deleted routine never throws
- Fixture: s-c alone. Expected: step completes; s-c unchanged. Edge case of: S-12210
### S-12212: Second run is a no-op
- Fixture: F-122 on a counting Mock subclass (records `updateSession` ids). Trigger: run twice.
- Expected: first run records `[s-a, s-f, s-i]` (any order, 3 calls); second run records 0. Edge of S-12210
### S-12213: Interrupted back-fill retries
- Fixture: Mock subclass whose `updateSession` throws on its 2nd call while `failing`; F-122;
  `setDataVersion(17)`. Trigger: `DataMigrationService(repository, targetVersion: currentDataVersion,
  steps: dataMigrationStepsForTest()).run()`.
- Expected: run throws; `getDataVersion() == 17`; exactly one of {s-a, s-f, s-i} stamped. Then
  `failing = false`, run again: completes; version == `currentDataVersion`; all 3 stamped; the row
  stamped first is written exactly once in total. Edge case of: S-12210
### S-12214: Version sequence and restart (Hive)
- Fixture: none / F-122. Expected: `currentDataVersion == 18`; Mock and Hive step lists identical as
  `version:name` and end `18:backfillRoutineSessionModality`; step 17 `retireOrphanTemplateRows` still
  present. Hive: F-122 staged, `setDataVersion(17)`, `harness.restart()` → version 18, s-a stamped
  (persisted). Red today.
### S-12215: Fresh install
- Fixture: freshly initialised store (both harnesses). Expected: version == 18; no session has
  `intent == 'routine'`; the step ran and changed nothing.
### S-12216: Focus edited after the back-fill
- Fixture: F-122 after one run; `updateTemplate(tpl-122-iso` with `focusModality: 'cardio_endurance')`.
- Trigger: run the step again. Expected: s-a and s-f stay `isometric_stretching` (D-12202).
- Edge case of: S-12212

### S-12217: Session overview add in a focused routine asks the kind (D-12205)
- Fixture: as S-12206 but `SessionOverviewScreen`. Trigger: add exercise, pick one.
- Expected: the dialog appears; the picker was built with `sessionModality == null` (D-12213). Red today
  with the stamped fixture. Edge case of: S-12206
### S-12218: Picker shows no Recommended section in a routine session (D-12213)
- Fixture: as S-12206, a catalog with exercises scoring above `RECOMMENDED_SCORE_THRESHOLD` for
  `isometric_stretching`. Trigger: open the picker from the add button.
- Expected: no "Recommended" header; one unranked list. Red with the stamped fixture. Edge of S-12206
### S-12219: Guards — home-tile modality session and Free Training (D-12205)
- Fixture: Mock; (i) session `intent: null`, `modality: 'isometric_stretching'`; (ii) `intent: null`,
  `modality: null`. Trigger: add exercise in each.
- Expected: (i) NO dialog, new effort `'drill'`, picker shows Recommended; (ii) dialog shown. Green today
  and must stay green (pins that only routine sessions changed). Edge case of: S-12206

## Iteration 1

### Phase 0: red tests (crew-builder-app; writes `test/**` only)
1. [ ] Record baselines in the evidence file: `flutter analyze` issue count; pass/fail of the Done Criteria suites.
2. [ ] Create `test/routine_session_modality_backfill_test.dart` with the F-122 builder and S-12207, S-12210 … S-12216 (plain `test()`, `harnessFactories`; counting/failing Mock subclasses as in `test/retire_orphan_template_rows_test.dart`).
3. [ ] Create `test/routine_session_modality_test.dart` with S-12201, S-12202, S-12203, S-12205, S-12206, S-12217, S-12218, S-12219 (Mock-only `testWidgets`) and S-12208 (plain `test()`). The add-exercise ones build their sessions with the stamped modality directly, so they do not depend on Phase 1.
4. [ ] Add S-12204 to `test/watch_routine_adoption_test.dart` (both harnesses); update S-3640's reason text only.
5. [ ] Run and paste the red table: expected RED = S-12201, S-12203, S-12204, S-12206, S-12207, S-12210-S-12216, S-12217, S-12218 (step lookup `StateError` / version 17; S-12206/S-12217/S-12218 because the dialog is skipped for a stamped fixture); expected GREEN = S-12202, S-12205, S-12208, S-12219. Any other outcome is logged and explained.

**Done Criteria:** `flutter test test/routine_session_modality_test.dart test/routine_session_modality_backfill_test.dart test/watch_routine_adoption_test.dart` shows exactly the expected red/green split; `flutter analyze` issue count ≤ baseline; AGENTS.md invariant checks clean.
**Predicted Files:** the three test files above; evidence file.

### Phase 1: start paths + home tile (crew-builder-app; ~15 production lines)
1. [ ] `lib/features/routine/my_routines_screen.dart` · `_startRoutine`: `modality: manifest.template.focusModality`; delete the "Mixed modality for routines" comment (D-12201a).
2. [ ] `lib/features/calendar/day_session_list_screen.dart` · `_tapPlanned` routine branch: same (D-12201b).
3. [ ] `lib/state/watch/watch_session_adoption_bridge.dart` · `_adopt`: `modality: routine?.template.focusModality`; extend the D-2 comment (D-12201c).
4. [ ] Run S-12205 now and record it RED in the evidence file; then `lib/features/home/home_screen.dart` tile `isActive` rule per D-12204; S-12205 green.
5. [ ] `lib/features/session/workout_session_list_view.dart` · `_sessionDisplayName` doc comment (:1000-1003): routine sessions now carry the Focus (comment only).
6. [ ] Fix-what-you-touch for `home_screen.dart` (UI Standards Impact).

**Done Criteria:** `flutter test test/routine_session_modality_test.dart test/watch_routine_adoption_test.dart test/watch_routine_round_trip_test.dart test/pr6_routine_session_entry_navigation_test.dart test/interaction_flow_test.dart test/health_yoga_kind_test.dart test/home_short_viewport_test.dart test/watch_session_adoption_build_notify_test.dart` all green; `flutter test test/screen_widget_test.dart --plain-name "DaySessionListScreen"` green; `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green; invariant grep empty; analyze ≤ baseline.
**Predicted Files:** the five `lib/` files above; `test/routine_session_modality_test.dart` (only if a fixture needs a fix, logged); plan Progress; evidence.

### Phase 1b: add-exercise keeps asking in routine sessions (crew-builder-app; ~12 production lines) — RUN BEFORE Phase 1
1. [ ] `lib/features/session/workout_session_screen.dart` · `_addExercise`: `askKind` per D-12205 (prompt when `session.modality == null` **or** `intent == 'routine'`; the existing rolling `preferredModality` branch stays for non-routine null-modality sessions); pass `sessionModality: askKind ? null : modality` to `ExercisePickerScreen` (D-12213).
2. [ ] `lib/features/session/session_overview_screen.dart` · `_addExercise`: same two changes; update the comment at :86 ("Free Training or Routine session (null modality)") to say routine sessions always ask.
3. [ ] Show S-12206, S-12217, S-12218 RED against the Phase 0 tree, then GREEN; paste both runs in the evidence file. (Stash of the two source files only if the gateway allows; otherwise cite the Phase 0 red run.)

**Done Criteria:** `flutter test test/routine_session_modality_test.dart` shows S-12206, S-12217, S-12218, S-12219 green (S-12201/S-12203 still red until Phase 1); `flutter test test/pr6_routine_session_entry_navigation_test.dart test/screen_widget_test.dart test/state_test.dart test/session_screen_build_phase_notify_test.dart test/pr4_session_controls_test.dart` green; invariant checks clean; analyze ≤ baseline.
**Predicted Files:** the two `lib/features/session/` files above; the new test file only if a fixture needs a fix (logged); evidence.

### Phase 2: back-fill service + version (crew-builder-app; ~60 production lines)
1. [ ] `lib/core/services/routine_session_modality_backfill.dart` · `RoutineSessionModalityBackfill(WorkoutRepository).run()` per D-12206/D-12208, doc comment carries the D-12209 label and retirement procedure.
2. [ ] `lib/core/constants/data_version.dart` · `currentDataVersion = 18` (D-12207 collision rule).
3. [ ] Update the version pins in `test/data_migration_test.dart` (S-156 group :547-571 → expect 18 and last step `backfillRoutineSessionModality`; the applied-step name lists ~:610-630 and ~:690-705 gain the new name; the S-8 sequence list :739-746 gains `18:backfillRoutineSessionModality`).
4. [ ] Update `test/retire_orphan_template_rows_test.dart:455-477` (S-19207): find step 17 by name instead of `steps.last`; the staged-at-16 install lands at `currentDataVersion`.

**Done Criteria:** service-level checks in `test/routine_session_modality_backfill_test.dart` that call the service directly are green; predicted intermediate state: S-12210-S-12216 step lookups and the updated pins in `test/data_migration_test.dart` stay RED until Phase 3 (state it in the evidence file with counts); analyze ≤ baseline.
**Predicted Files:** the service, `data_version.dart`, the two pinned test files.

### Phase 3: wire the step (crew-builder-data; ~12 production lines)
1. [ ] `lib/data/repositories/hive_workout_repository.dart` · `_dataMigrationSteps()`: append `_MethodStep(18, 'backfillRoutineSessionModality', () => RoutineSessionModalityBackfill(repo).run())` with the D-12209 label comment.
2. [ ] `lib/data/repositories/mock_workout_repository.dart` · `_dataMigrationSteps()`: append the matching `_MockMigrationStep`; update the "steps 15, 16 and 17 run the same bodies" comment.
3. [ ] Show S-12210 red→green by stashing item 1-2 only if the gateway allows; otherwise cite the Phase 0 red run.

**Done Criteria:** `flutter test test/routine_session_modality_backfill_test.dart test/routine_session_modality_test.dart test/data_migration_test.dart test/retire_orphan_template_rows_test.dart test/watch_routine_adoption_test.dart test/db_seed_test.dart test/repository_reference_revision_test.dart` all green; invariant checks clean; analyze ≤ baseline.
**Predicted Files:** the two repositories; evidence.

### Phase 4: docs + residue sweep (crew-docs-keeper)
1. [ ] `docs/my_routines.md` (27.5 KB): Decision 3 gains "a routine session's modality is the routine's Focus at start, a snapshot" with pointers S-12201/S-12202/S-12203; "Active State Detection" gains D-12204 with pointer S-12205; one line: adding an exercise in a routine session always asks the kind and lists unranked, whatever the Focus (D-12205/D-12213, Q1 = A), pointers S-12206/S-12217-S-12219.
2. [ ] `docs/calendar_periods.md` (13 KB): routine sessions are coloured/labelled by their Focus; planned routine entries are not (pointer S-12207).
3. [ ] `docs/db_integration.md` (45.4 KB): a `backfillRoutineSessionModality` subsection labelled "ONE-OFF (plan 122) — retire after launch" with rule, idempotency, retirement procedure (D-12209) and pointers S-12210-S-12214; update the two "most recent step" sentences (~:257 and ~:704).
4. [ ] `docs/constants_reference.md` (27.8 KB) `currentDataVersion` row (:596); `docs/data_models.md` (48.1 KB) `### TrainingSession`: one lifecycle line — routine sessions freeze the Focus at start (D-12202).
5. [ ] Size check: `wc -c` of every touched doc < 53 248 bytes (52 KB band; data_models.md is closest); `flutter test test/docs_indexing_contract_test.dart` green.
6. [ ] Residue sweep: `grep -rn "Mixed modality for routines\|carry the routine name in .title. (and a null" lib` → 0; `grep -rn "modality: null" lib/features/routine lib/features/calendar/day_session_list_screen.dart` → 0 routine-start hits.

**Done Criteria:** items 5-6 output pasted; `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green.
**Predicted Files:** the five docs; evidence.

## Files Affected

Production: `lib/features/routine/my_routines_screen.dart`, `lib/features/calendar/day_session_list_screen.dart`,
`lib/state/watch/watch_session_adoption_bridge.dart`, `lib/features/home/home_screen.dart`,
`lib/features/session/workout_session_list_view.dart` (comment), `lib/features/session/workout_session_screen.dart` and `session_overview_screen.dart` (Phase 1b), `lib/core/services/routine_session_modality_backfill.dart` (new),
`lib/core/constants/data_version.dart`, `lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`.
Tests: two new files; `watch_routine_adoption_test.dart`, `data_migration_test.dart`, `retire_orphan_template_rows_test.dart`.
Read-only dependents: `calendar_state.dart`, `calendar_screen.dart`, `health_sync_service.dart`, `exercise_picker_screen.dart`, `session_core_entry.dart`.
Not touched: `scripts/sqlite_schema.sql` / `sqlite_seed.sql` (no schema change), `models.dart`, `watch/`.

## Notes

- Dependency graph: 0 → 1b → 1 → 2 → 3 → 4 (1b first: it is a no-op until Phase 1 stamps, and Phase 1 without it would silently drop the kind question). Phase 1 and Phases 2-3 are independent of each other; running
  2-3 first ships the back-fill before new sessions are stamped (harmless; one launch of drift for
  sessions started in between). Run 3 immediately after 2 (Phase 2 leaves predicted reds).
- Plan 118 (uncommitted in the same tree) asserts `lib/core/constants/data_version.dart` unchanged in its
  footprint gate: do not start Phase 2 until 118 is committed or its gate has run.
- Legacy: no installs depend on null routine modality; the only test asserting null uses a no-focus
  template (unchanged).

- Sequencing with sibling plans: plan 123 (routine editor Mixed / Not set clears the Focus) lands BEFORE
  or WITH Phase 2; plan 124 (planned calendar entries) is separate (D-12214).
- Scope budget (re-checked after the amendment): hard limits — plan ≈ 440 lines (< 800), 5 implementation
  phases (1, 1b, 2, 3, 4; Phase 0 is tests only; limit is "more than 5"), ≈ 140 predicted production
  lines (< 1 500): none hit. Soft signals: only "more than 3 phases" is present (one track, ≈ 14
  decisions, 19 scenarios): fewer than two, so NO split. If the plan grows past 500 lines or a sixth
  phase is needed, split into PR A = Phase 0 + 1b + 1 (stamping and add-exercise guard) and PR B =
  Phases 2-4 (back-fill, wiring, docs); PR B waits for plan 123.

## Noticed, not planned

1. (now plan 123) "Mixed / Not set" may not clear a routine's Focus: `RoutineState.updateRoutineFocusModality(null)`
   (`routine_state.dart:213-221`) uses `WorkoutTemplate.copyWith(focusModality: null)`, which keeps the
   old value (`models.dart:740`, `??`), and `saveRoutine` writes `_currentTemplate`. Not run; no test
   covers it. Interacts with this plan (stale focus would be stamped) — worth a small plan landing first.
2. (now plan 124) A planned (not started) routine entry in the calendar still shows "Free Training" (routine mode
   stores `modality: null`, `day_session_list_screen.dart:922`).
3. Wrist-started routines carry no Focus on the wrist or in its own Health workout (`routines_down` has
   no field; `WatchStartPaths.swift:557`) — sync-contract track.
4. `session_summary_builder.dart:193` falls back to the raw key (`'isometric_stretching'`) rather than a
   display name when a session has no title.

## Progress
- [x] Phase 0 · [x] Phase 1b · [x] Phase 1 · [x] Phase 2 · [x] Phase 3 · [x] Phase 4 · [x] review (APPROVE, see .review.md)

## Assumption Log

- Version 18 was free (HEAD `b51b02ea`, `currentDataVersion` was 17; plan 118 committed).
- D-12201(c) is applied in `_adopt` only. Plan 129's `_startSessionRow` (wrist `session_started` path, uncommitted, not ours) also opens a routine session without a modality; a wrist-started routine whose row is opened there first is not stamped, and `_adopt` then finds the row held. Left to plan 129 / a follow-up.
- S-12205 was red before Phase 1 (the fixture is already stamped), not green as predicted.
- The rolling `preferredModality` branch in `workout_session_screen.dart` also gained `!isRoutineSession` (defensive, unreachable for routines).
- `home_screen.dart` was in `colorsBlackRatchet` (3); fixed in Phase 1 (`colorScheme.shadow`), entry removed from `test/helpers/ui_standards_allowlist.dart`.
- Defaults taken (vetoable): D-12213 unranked picker; D-12210 Health type accepted.
- Lead added S-12210 empty-Focus case after the mutation pass left the `focus.isEmpty` guard unguarded.

## Feedback
