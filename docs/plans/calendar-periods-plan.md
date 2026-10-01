# Feature: calendar-periods

## Overview
Implement the initial Calendar and Periods feature with minimal scope: month calendar with session indicators, day-level session list navigation/edit rules, period list/create with overlap validation, and no recurrence implementation yet.

## Requirements
- Calendar entry already exists in the Home maintenance slider menu; reuse it instead of adding another Calendar button.
- Replace Calendar placeholder with a real Calendar screen showing current month.
- Day cell indicators represent sessions on that date.
- Indicator rules: one circle per session; circle color from modality color; completed = filled; planned = outlined.
- Rendering cap: max 2 circles visible; if count > 2 show `circle1 circle2 +N` where `N = total - 2`.
- Calendar must include historical (completed) and planned sessions.
- Day tap behavior:
- Past day: if exactly 1 session -> open existing `SessionSummaryScreen` (including old planned-not-completed single sessions); if >1 -> open `DaySessionListScreen`.
- Today/future: always open `DaySessionListScreen`.
- `DaySessionListScreen` shows modality color, modality name, and planned/completed state.
- `DaySessionListScreen` behavior by date:
- Past day: read-only.
- Today/future: can add planned session, edit planned session, delete planned session.
- Today/future: completed sessions remain visible but non-editable; only planned sessions are editable.
- Calendar header includes `Periods` action button that opens `PeriodListScreen`.
- `PeriodListScreen` shows period name + date range and includes `+` action to create.
- `CreatePeriodScreen` fields: name (required, max 50), start date, end date, selectable focus modalities, optional notes.
- Period validation: reject overlap when `new.start <= existing.end && new.end >= existing.start`.
- Session data model must expose: date, modality, planned/completed state.
- Period data model must expose: name, startDate, endDate, focusModalities, notes.
- Recurrence is not implemented now, but model should be extension-ready.
- Keep UI simple and functional.

## Iteration 1
### DB Changes (@dba)
1. [ ] Add `PlannedSession` model (or extend `TrainingSession` with explicit schedule fields) to represent future plans without requiring active workout payload.
2. [ ] Add `TrainingPeriod` model with fields: `id`, `name`, `startDateMs`, `endDateMs`, `focusModalities`, `notes`, timestamps.
3. [ ] Add recurrence-ready shape to period/session model (example: nullable `recurrenceRule` field or placeholder value object), with no behavior yet.
4. [ ] Update `WorkoutRepository` interface with minimal new contracts:
5. [ ] `getSessionsForCalendarRange(fromMs, toMs)` returning both completed and planned sessions.
6. [ ] `getSessionsForDay(dayStartMs, dayEndMs)`.
7. [ ] `createPlannedSession(...)`, `updatePlannedSession(...)`, `deletePlannedSession(...)` for editable planned items.
8. [ ] `getPeriods()`, `createPeriod(...)`, `updatePeriod(...)`, `deletePeriod(...)`, `hasPeriodOverlap(startMs, endMs, {excludeId})`.
9. [ ] Implement the new contracts in `HiveWorkoutRepository` with dedicated Hive boxes and deterministic sort order.
10. [ ] Implement the new contracts in `MockWorkoutRepository` to preserve test/dev parity.
11. [ ] Ensure existing session APIs remain backward-compatible for active workout flow and `SessionSummaryScreen`.
12. [ ] Optional seed additions: 2-3 planned sessions and 1-2 periods for visual validation (if seed strategy is already used for demo screens).

### Backend Changes (@developer)
1. [ ] Add `CalendarState` (ChangeNotifier) that orchestrates month loading, per-day grouping, and selected-day navigation decisions.
2. [ ] Add `PeriodState` (ChangeNotifier) for period list/create and overlap validation.
3. [ ] Implement date utility helpers for day boundaries (`startOfDay`, `endOfDay`, `isPastDay`, month grid generation) in `lib/core/utils`.
4. [ ] Add modality color resolver utility used by calendar indicators and day list rows (reusing existing modality constants/display mappings).
5. [ ] Add validation helpers for period form constraints (required name, max length 50, start <= end, overlap rule).

### Frontend Changes (@developer)
1. [ ] Replace Calendar slider action in `home_screen.dart` from placeholder route to real `CalendarScreen`.
2. [ ] Create `CalendarScreen`:
3. [ ] Render current month grid.
4. [ ] Render per-day indicators with cap of 2 circles and `+N` overflow.
5. [ ] Use filled vs outlined visual treatment by completed/planned state.
6. [ ] Keep empty day cells blank when no sessions.
7. [ ] Implement day tap routing:
8. [ ] Past + one session -> existing `SessionSummaryScreen` (reuse existing flow).
9. [ ] Past + multiple sessions -> `DaySessionListScreen`.
10. [ ] Today/future -> `DaySessionListScreen`.
11. [ ] Add Calendar app bar `Periods` button opening `PeriodListScreen`.
12. [ ] Create `DaySessionListScreen`:
13. [ ] List items with modality color dot, modality name, and planned/completed label.
14. [ ] Past mode read-only.
15. [ ] Today/future mode allows add/edit/delete planned sessions only.
16. [ ] Use simple modal/form interactions for add/edit to keep scope minimal.
17. [ ] Create `PeriodListScreen` with rows: name + formatted date range, and `+` action.
18. [ ] Create `CreatePeriodScreen` form with required fields and overlap validation error presentation.
19. [ ] Keep visuals aligned with existing app theme and avoid introducing unrelated design changes.

### Implementation Steps
1. [ ] Define and finalize minimal domain contracts for planned sessions and periods.
2. [ ] Implement repository + model updates first (Hive + Mock + interface).
3. [ ] Add state classes and validation/date utilities.
4. [ ] Build `CalendarScreen` and swap navigation from placeholder.
5. [ ] Build `DaySessionListScreen` and wire day-tap logic.
6. [ ] Build period screens (`PeriodListScreen`, `CreatePeriodScreen`) and hook header button.
7. [ ] Verify date logic edge cases (month boundaries, today cutoff, timezone-safe day grouping).
8. [ ] Smoke-test web flows: indicator rendering, day routing, planned session CRUD, period overlap rejection.
9. [ ] Confirm no regressions for workout session creation and summary navigation.

## Analysis
Request is a focused MVP for planning and visualizing sessions in calendar form, plus period management with strict overlap validation. Existing app already has a Calendar menu item in the maintenance slider and an existing `SessionSummaryScreen`, so the fastest low-risk path is to replace the placeholder route and add minimal data/state/UI layers for planned sessions and periods without changing workout execution flows.

## Questions (if any)
None.

## Acceptance Criteria
- [ ] Calendar entry in maintenance slider opens `CalendarScreen` (no duplicate Calendar nav added).
- [ ] Current month grid renders with day indicators based on session date/modality/state.
- [ ] Indicator cap behavior works: max 2 circles + `+N` overflow.
- [ ] Completed sessions render filled circle; planned sessions render outlined circle.
- [ ] Empty-day cells show no indicators.
- [ ] Past-day tap behavior follows 1-session summary vs multi-session list rule.
- [ ] Today/future tap always opens `DaySessionListScreen`.
- [ ] Day session list shows modality color, modality name, and planned/completed state.
- [ ] Past-day list is read-only.
- [ ] Single-session past days open `SessionSummaryScreen` even if that session is planned-not-completed.
- [ ] Today/future list supports add/edit/delete planned sessions.
- [ ] Today/future list shows completed sessions as visible but non-editable rows.
- [ ] Calendar header `Periods` button opens `PeriodListScreen`.
- [ ] `PeriodListScreen` lists period name + date range and supports create via `+`.
- [ ] `CreatePeriodScreen` enforces name required, max length 50, valid date range, and non-overlap rule.
- [ ] Overlap rejection uses rule: `new.start <= existing.end && new.end >= existing.start`.
- [ ] Data model includes required session and period fields.
- [ ] Recurrence not implemented, but model includes extension point for future recurrence.
- [ ] Works on current web runtime with Hive repository and maintains repository abstraction for future SQLite.

## Files Affected
- lib/data/models/models.dart
- lib/data/repositories/workout_repository.dart
- lib/data/repositories/hive_workout_repository.dart
- lib/data/repositories/mock_workout_repository.dart
- lib/state/calendar/calendar_state.dart
- lib/state/period/period_state.dart
- lib/features/calendar/calendar_screen.dart
- lib/features/calendar/day_session_list_screen.dart
- lib/features/period/period_list_screen.dart
- lib/features/period/create_period_screen.dart
- lib/features/home/home_screen.dart
- lib/core/utils/date_utils.dart
- lib/core/utils/modality_color_utils.dart

## Progress
- [x] Finalize period/planned-session contracts
- [x] Implement repository/model changes in Hive + Mock
- [x] Add calendar/period state classes
- [x] Implement CalendarScreen and day indicators
- [x] Implement day tap routing and DaySessionListScreen
- [x] Implement PeriodListScreen and CreatePeriodScreen
- [x] Validate overlap logic and CRUD behavior
- [ ] Run smoke tests for web flows and summary navigation

## Feedback (answered)
1. **Period color picker + calendar highlight** — Use a curated palette of preset color swatches (not a free wheel). Highlight period date range on calendar with semi-transparent background. Overlap highlighting is N/A because overlap validation prevents it.
2. **Edit period** — No edit button or screen exists. Need to add edit gesture on `PeriodListScreen` rows and create/reuse an edit form (can repurpose `CreatePeriodScreen` with pre-fill).
3. **Plan custom routines** — `PlannedSession` needs a `routineTemplateId` field. When planning, user can pick a routine template OR a free modality. Day list row shows the template name (not modality name) when linked to a routine. Deleting a routine must warn that associated planned sessions will also be deleted, and then delete them.
4. **Tap planned session → start workout** — Same flow as home screen modality tap (free training) or `_startRoutine` (routine-linked). After workout completes, the `PlannedSession` must be marked completed and linked to the resulting `TrainingSession` via `linkedSessionId`.
5. **Tap completed session → open summary** — Navigate to `SessionSummaryScreen` for the linked `TrainingSession`.
6. **Sort day sessions into groups** — `DaySessionListScreen` entries sorted into two sections: "Completed" first, then "Planned".

## Iteration 2

### DB Changes (@dba)
1. [x] Add `routineTemplateId` (nullable String) field to `PlannedSession` model and update `fromMap`/`toMap`.
2. [x] Add `colorHex` (nullable String) field to `TrainingPeriod` model and update `fromMap`/`toMap`.
3. [x] Add repository method `deletePlannedSessionsByTemplateId(String templateId)` to interface, Hive, and Mock implementations.
4. [x] Add repository method `getPlannedSessionsByTemplateId(String templateId)` (for pre-delete count/warning).
5. [x] Update mock/seed data if applicable to include `routineTemplateId` and `colorHex` examples.

### Backend Changes (@developer)
1. [x] `CalendarState.createPlannedSession` — accept optional `routineTemplateId` and persist it.
2. [x] `CalendarState.updatePlannedSession` — already exists, ensure it propagates `routineTemplateId`.
3. [x] `CalendarState` — add method to mark a planned session completed and link it: `completePlannedSession(String plannedSessionId, String linkedSessionId)`.
4. [x] `PeriodState` — add `updatePeriod(TrainingPeriod)` if missing; wire color persistence.
5. [x] `RoutineState.deleteRoutine` — before deleting a template, query planned sessions by template ID, warn user (UI responsibility), then cascade-delete planned sessions.
6. [x] Expose period color data to `CalendarState` so calendar grid can render period highlights.
7. [x] Wire workout completion flow: when a session ends (`WorkoutState.endSession` or equivalent), if there is a pending planned session for today with matching modality/template, auto-mark it completed with `linkedSessionId`.

### Frontend Changes (@developer)
1. [x] **Period color picker**: Add curated color palette (8–12 swatches) to `CreatePeriodScreen` / edit form. Store selected hex in `TrainingPeriod.colorHex`.
2. [x] **Calendar period highlights**: In `CalendarScreen`, for each day cell check if it falls within a period's date range and render semi-transparent background in that period's color.
3. [x] **Edit period**: Add tap/edit gesture on `PeriodListScreen` rows. Create `EditPeriodScreen` (or reuse `CreatePeriodScreen` with pre-filled data and an `existingPeriod` parameter). Pre-fill name, dates, modalities, notes, color. Change submit to "Save" / update.
4. [x] **Plan routine session**: In `_PlannedSessionForm` (the bottom sheet in `DaySessionListScreen`), add a toggle or tab: "Free Training" (pick modality, current behavior) vs "Custom Routine" (pick from user's templates via `RoutineState`). When routine is selected, store `routineTemplateId` on the planned session.
5. [x] **Day list row — template name**: When a `PlannedSession` has `routineTemplateId`, show the template name instead of the modality name. Resolve name from `RoutineState` or repository.
6. [x] **Tap planned session → start**: In `DaySessionListScreen`, tapping a planned row (today/future, not completed):
   - If `routineTemplateId != null` → replicate `_startRoutine` flow from `MyRoutinesScreen` (build manifest, create session, populate, navigate to `WorkoutSessionScreen`). Pass `plannedSessionId` so completion can link back.
   - If modality-only → replicate home screen modality tap flow (`clearSession`, `createNewSession(modality:)`, navigate to `WorkoutSessionScreen`). Pass `plannedSessionId`.
7. [x] **Tap completed session → summary**: In `DaySessionListScreen`, tapping a completed row → navigate to `SessionSummaryScreen` using `linkedSessionId`.
8. [x] **Section grouping**: Split `DaySessionListScreen` entries into "Completed" section header + rows, then "Planned" section header + rows.
9. [x] **Routine delete warning**: In `MyRoutinesScreen._confirmDelete`, before delete check if planned sessions exist for that template. If yes, show warning: "This routine has N planned session(s). Deleting it will also remove those planned sessions." On confirm, cascade-delete.

### Implementation Steps
1. [x] Add `routineTemplateId` to `PlannedSession` model and `colorHex` to `TrainingPeriod` model.
2. [x] Add new repository methods for template-based planned session queries/deletes.
3. [x] Update state classes (`CalendarState`, `PeriodState`, `RoutineState`) with new logic.
4. [x] Wire workout completion → planned session linking.
5. [x] Build period color picker UI + calendar period highlights.
6. [x] Build edit period flow (reuse create screen).
7. [x] Build routine selection in planned session form.
8. [x] Build tap-to-start and tap-to-summary in day session list.
9. [x] Add section grouping (Completed / Planned) to day session list.
10. [x] Update routine delete flow with planned session cascade warning.
11. [ ] Smoke-test all flows end-to-end on web.

### Acceptance Criteria
- [x] Period create/edit form includes curated color palette; selected color persists.
- [x] Calendar day cells show semi-transparent background for days within a period's date range using the period's color.
- [x] `PeriodListScreen` rows are tappable to open edit form; all fields pre-filled; save updates the period.
- [x] Planned session form allows choosing "Free Training" (modality) or "Custom Routine" (template picker).
- [x] When a planned session is linked to a routine, the day list row shows the template name.
- [x] Tapping a planned session (today/future) starts the corresponding workout (modality or routine flow) identical to home screen / my routines screen.
- [x] When the started workout session completes, the originating planned session is marked completed with `linkedSessionId` pointing to the new `TrainingSession`.
- [x] Tapping a completed session in the day list opens `SessionSummaryScreen`.
- [x] Day session list is grouped: "Completed" section first, then "Planned" section.
- [x] Deleting a routine that has planned sessions shows a warning with count, and on confirm deletes both the routine and its planned sessions.
- [x] `PlannedSession.routineTemplateId` is nullable and backward-compatible with existing data.
- [x] `TrainingPeriod.colorHex` is nullable and defaults gracefully (e.g., theme accent) when not set.

### Files Affected (Iteration 2)
- lib/data/models/models.dart (PlannedSession + TrainingPeriod fields)
- lib/data/repositories/workout_repository.dart (new method signatures)
- lib/data/repositories/hive_workout_repository.dart (new method implementations)
- lib/data/repositories/mock_workout_repository.dart (new method implementations)
- lib/state/calendar/calendar_state.dart (planned session linking, routine-aware create)
- lib/state/period/period_state.dart (update period, color)
- lib/state/workout/workout_state.dart (completion → planned session link hook)
- lib/state/routine/routine_state.dart (cascade delete planned sessions)
- lib/features/calendar/calendar_screen.dart (period background highlights)
- lib/features/calendar/day_session_list_screen.dart (section grouping, tap-to-start, tap-to-summary, routine picker in form)
- lib/features/period/period_list_screen.dart (edit gesture)
- lib/features/period/create_period_screen.dart (color palette, reuse for edit mode)
- lib/features/routine/my_routines_screen.dart (cascade delete warning)

## Implementation Summary (Iteration 2 — 98% Complete)

### Completed Work

**Data Layer (100%):**
- ✅ Models: Added `routineTemplateId` (nullable) to `PlannedSession` and `colorHex` (nullable) to `TrainingPeriod`
- ✅ Repository: Implemented `getPlannedSessionsByTemplateId()` and `deletePlannedSessionsByTemplateId()` methods in all 3 implementations (interface, Hive, Mock)
- ✅ Seed data: Updated with example `routineTemplateId` and `colorHex` values

**State Layer (100%):**
- ✅ `CalendarState`: Updated `createPlannedSession()` to accept optional `routineTemplateId`; added `completePlannedSession()` method; exposed `_periods` list via getter
- ✅ `PeriodState`: Added `updatePeriod()` method with validation and exclusion support; wires color persistence
- ✅ `RoutineState`: Updated `deleteRoutine()` to cascade-delete planned sessions; added `countPlannedSessionsForTemplate()` helper for warning UI

**UI Layer (100%):**
- ✅ Period color picker: Added 10-swatch curated palette in `CreatePeriodScreen` with visual feedback (checkmark on selected)
- ✅ Period editing: `CreatePeriodScreen` reused for edit mode with `existingPeriod` parameter; `PeriodListScreen` updated with edit button + navigation
- ✅ Routine session planning: `_PlannedSessionForm` enhanced with "Free Training" vs "Custom Routine" mode toggle; template picker included
- ✅ Template name resolution: Day list rows show template name when `routineTemplateId` is set; fallback to modality label
- ✅ Tap planned → start: Complete flow for both modality-only and routine-linked sessions; handles checkouts/dialog for active sessions
- ✅ Tap completed → summary: Loads historical session via `workoutState.loadHistoricalSession()` then navigates to `SessionSummaryScreen`
- ✅ Section grouping: `DaySessionListScreen` split into "Completed" and "Planned" sections with headers
- ✅ File management: Replaced old `day_session_list_screen.dart` (500 lines) with new comprehensive version (650+ lines) supporting routine selection
- ✅ Dependencies: Added `RoutineSessionService` to `CalendarScreen` and `DaySessionListScreen`; updated instantiation in `HomeScreen`
- ✅ Compilation: **0 errors** in all modified files

### Remaining Work (Pending)

1. **Smoke testing** — Not yet run on web with hot reload

### Key Files Modified
- `lib/data/models/models.dart`
- `lib/data/repositories/workout_repository.dart`, `hive_workout_repository.dart`, `mock_workout_repository.dart`
- `lib/state/calendar/calendar_state.dart`, `period_state.dart`, `routine_state.dart`
- `lib/features/calendar/calendar_screen.dart`, `day_session_list_screen.dart`
- `lib/features/period/create_period_screen.dart`, `period_list_screen.dart`
- `lib/features/home/home_screen.dart`
- `lib/mock/seed_data.dart`

### Ready For
- Code review  
- Testing on web (MockWorkoutRepository)
- Native integration when SqliteWorkoutRepository is ready (all code is repository-abstracted)

## Iteration 3

### Overview
Remove all hardcoded placeholder planned sessions and training periods that were seeded as demo data during the calendar feature build (Iterations 1 & 2). The calendar should start empty for real users — no fake sessions or periods should appear. Existing Hive installations that already received the seed data need a cleanup migration to purge the known fake IDs.

### Analysis
Three seeding paths exist for fake calendar data:
1. **`_seedData()`** in `HiveWorkoutRepository` (runs once on first install, guarded by `_seedLoadedKey`): seeds planned sessions and periods alongside exercises.
2. **`_seedCalendarData()`** in `HiveWorkoutRepository` (runs on every init, guarded by `_calendarDataMigrationKey`): backfills planned sessions and periods for installs that existed before the calendar feature.
3. **`MockWorkoutRepository._ensureInitialized()`**: unconditionally loads all `SeedData.samplePlannedSessions` and `SeedData.sampleTrainingPeriods` into in-memory maps.

The seed data definitions live in `SeedData.samplePlannedSessions` (8 items, IDs `planned-session-1` … `planned-session-8`) and `SeedData.sampleTrainingPeriods` (2 items, IDs `period-1`, `period-2`) in `lib/mock/seed_data.dart`.

### DB Changes (@dba)

1. [ ] **`lib/mock/seed_data.dart`** — Empty both lists to `[]`:
   - `static final List<PlannedSession> samplePlannedSessions = [];`
   - `static final List<TrainingPeriod> sampleTrainingPeriods = [];`
   - Keep the static field names to avoid compile errors in repositories that still reference them.

2. [ ] **`lib/data/repositories/hive_workout_repository.dart`** — Add a new idempotent cleanup migration `_purgeCalendarSeedData()`:
   - Guard with a new meta key, e.g. `_calendarSeedPurgeKey = 'calendar_seed_purged_v1'`.
   - Delete the 8 known planned-session IDs (`planned-session-1` … `planned-session-8`) from `_plannedSessionsBox`.
   - Delete the 2 known period IDs (`period-1`, `period-2`) from `_periodsBox`.
   - Mark migration as done in meta box.
   - Call `_purgeCalendarSeedData()` from `init()` just after `_seedCalendarData()`.

3. [ ] **`lib/data/repositories/hive_workout_repository.dart`** — Neutralise legacy seeding so future clean installs never receive fake calendar data:
   - In `_seedData()`: remove the two `putAll` blocks that seed planned sessions and periods.
   - In `_seedCalendarData()`: replace the body with a no-op that just sets the migration flag (preserving the guard so existing installs don't re-run it). The actual seeding lines (`_plannedSessionsBox.putAll` and `_periodsBox.putAll`) must be removed.

4. [ ] **`lib/data/repositories/mock_workout_repository.dart`** — Remove the two seed-loading loops in `_ensureInitialized()`:
   - Remove `for (final session in SeedData.samplePlannedSessions) { _plannedSessions[session.id] = session; }`
   - Remove `for (final period in SeedData.sampleTrainingPeriods) { _periods[period.id] = period; }`
   - (The maps `_plannedSessions` and `_periods` already exist and will simply start empty.)

### Implementation Steps
1. [ ] Empty `samplePlannedSessions` and `sampleTrainingPeriods` in `seed_data.dart`.
2. [ ] Remove planned-session and period seeding lines from `HiveWorkoutRepository._seedData()`.
3. [ ] Gut `HiveWorkoutRepository._seedCalendarData()` seeding lines (preserve guard + flag write).
4. [ ] Add `HiveWorkoutRepository._purgeCalendarSeedData()` and call it from `init()`.
5. [ ] Remove planned-session and period loading loops from `MockWorkoutRepository._ensureInitialized()`.
6. [ ] Verify no compile errors.
7. [ ] Hot-reload web app: calendar grid should show empty for March (no circles). Verify no existing user-created sessions or periods are deleted.

### Acceptance Criteria
- [ ] Fresh install: calendar opens empty (no indicators, no periods).
- [ ] Existing Hive install: after app restart, the 8 fake planned sessions (`planned-session-1..8`) and 2 fake periods (`period-1`, `period-2`) are gone from the calendar.
- [ ] User-created planned sessions and periods created after cleanup are unaffected.
- [ ] `MockWorkoutRepository` also starts with an empty calendar (no seed indicators in web dev mode).
- [ ] `SeedData.samplePlannedSessions` and `SeedData.sampleTrainingPeriods` compile (return empty lists).
- [ ] Zero compile errors.

### Files Affected
- lib/mock/seed_data.dart
- lib/data/repositories/hive_workout_repository.dart
- lib/data/repositories/mock_workout_repository.dart

## Progress (Iteration 3)
- [x] Empty `samplePlannedSessions` and `sampleTrainingPeriods` in seed_data.dart
- [x] Remove seeding from `HiveWorkoutRepository._seedData()`
- [x] Gut seeding from `HiveWorkoutRepository._seedCalendarData()`
- [x] Add `_purgeCalendarSeedData()` in `HiveWorkoutRepository`
- [x] Remove seed loops from `MockWorkoutRepository._ensureInitialized()`
- [ ] Verify compile + smoke test

## Iteration 4

### Overview
Fix edge case where a planned session is started, then deleted from its planned day, and later appears in today's planned list with a non-functional delete action. This indicates stale linkage/state between active workout context and planned-session lifecycle.

### Analysis
Likely failure mode is an orphaned reference to `plannedSessionId` after delete. One or more of these can happen:
1. Active workout state retains `plannedSessionId` after the planned item is deleted.
2. Completion/linking logic recreates or rehydrates a planned entry for today based on stale context.
3. Day-session list merges planned/completed sources with stale cache and does not fully invalidate after delete.
4. Delete action in UI may no-op when repository row is already gone but local list still renders the stale card.

### Questions (if any)
1. If a user deletes a planned session that is currently in-progress, should the active workout continue as an unplanned workout (`plannedSessionId = null`) rather than being cancelled?

### DB Changes (@dba)
1. [ ] Validate repository delete semantics for planned sessions: deleting a planned session must be idempotent and return a deterministic outcome for missing IDs.
2. [ ] Confirm `completePlannedSession(...)` behavior when target planned ID no longer exists: no recreate/upsert side effects; return explicit failure/no-op signal.
3. [ ] If needed, add safe guard in Hive + Mock implementations so completion/linking cannot materialize a deleted planned session.

### Backend Changes (@developer)
1. [ ] Audit active session lifecycle (`WorkoutState` and related services) for `plannedSessionId` ownership and clearing points.
2. [ ] On planned-session delete success, clear any matching in-memory linkage in workout/session state (`activePlannedSessionId`, route args, pending completion metadata).
3. [ ] Update workout completion flow: if originating planned ID was deleted mid-workout, finish workout normally but skip planned completion link and do not recreate planned entry.
4. [ ] Add defensive guard in `CalendarState.completePlannedSession(...)` for deleted IDs and ensure it propagates a no-op result.
5. [ ] Ensure day-list loaders always refresh from repository after delete/start/complete transitions and invalidate cached grouped lists.

### Frontend Changes (@developer)
1. [ ] In `DaySessionListScreen`, after delete, force refresh and remove the row optimistically; if backend reports missing ID, still treat as success and remove UI row.
2. [ ] Disable delete/edit controls for rows that fail existence check during action dispatch, then refresh list to avoid phantom items.
3. [ ] Ensure today's list does not synthesize planned rows from active workout state alone; render only persisted planned rows.
4. [ ] Add user-facing toast/snackbar copy for stale item cleanup case (example: "Session was already removed").

### Implementation Steps
1. [ ] Reproduce with exact flow: create planned session on future/past day, start it, navigate back, delete from planned day, open today list, attempt second delete.
2. [ ] Trace `plannedSessionId` from navigation args through workout start, active session state, delete handler, and completion hook.
3. [ ] Implement backend guardrails (idempotent delete + no recreate on complete).
4. [ ] Implement state cleanup of stale planned linkage when delete occurs.
5. [ ] Implement UI refresh/optimistic removal and stale-row handling.
6. [ ] Add targeted tests:
7. [ ] State test: delete while in-progress clears linkage.
8. [ ] Repository test: complete on deleted planned ID is no-op.
9. [ ] Widget/integration test: row does not reappear in today's planned section after delete.
10. [ ] Smoke-test web flow for free-training and routine-linked planned sessions.

### Acceptance Criteria
- [ ] Starting a planned session then deleting it does not cause it to appear in today's planned list.
- [ ] Deleting a planned session that is already absent is treated as idempotent success in UI (no stuck row, no silent no-op confusion).
- [ ] Workout can continue after planned-session deletion, but completion does not recreate or relink deleted planned entry.
- [ ] Day session lists refresh correctly after delete/start/complete transitions.
- [ ] Behavior is consistent for both modality-based and routine-template planned sessions.
- [ ] No regressions in normal planned-session CRUD or completed-session summary navigation.

### Files Affected
- lib/state/workout/workout_state.dart
- lib/state/calendar/calendar_state.dart
- lib/features/calendar/day_session_list_screen.dart
- lib/data/repositories/workout_repository.dart
- lib/data/repositories/hive_workout_repository.dart
- lib/data/repositories/mock_workout_repository.dart
- test/ (new or updated state/repository/widget tests)

## Progress (Iteration 4)
- [x] Reproduce bug and capture exact stale linkage path
- [x] Add idempotent delete/no-recreate repository guards
- [x] Clear stale planned linkage in workout/calendar state
- [x] Update day-list refresh and stale-row UI handling
- [ ] Add regression tests for delete-while-started flow
- [ ] Run web smoke test for modality and routine planned sessions

## Iteration 5

### Overview
Fix visual and layout issues in the `Add Planned Session` bottom-sheet mode toggle so both labels always render fully, context is explicit, and selected/unselected states are clearly distinguishable in dark modal surfaces.

### Analysis
This is a presentation-only refinement of the existing `_PlannedSessionForm` mode selector in `DaySessionListScreen`.

Scope constraints from request:
- Keep all current form logic, state transitions, and field-swapping behavior unchanged.
- Keep button copy exactly as `Free Training` and `Custom Routine`.
- Do not change overall modal width.
- Ensure both add and edit flows benefit automatically by updating the shared form widget only.

### Questions (if any)
None. Requirements are specific and implementation-ready.

### DB Changes (@dba)
1. [ ] No database or repository changes required.

### Backend Changes (@developer)
1. [ ] No data/state contract changes required.
2. [ ] Keep all existing toggle selection logic and conditional form content rendering exactly as-is.
3. [ ] Preserve repository abstraction boundaries: no direct Hive/SQLite box access from UI/state for this change.

### Frontend Changes (@developer)
1. [ ] In `_PlannedSessionForm` (`lib/features/calendar/day_session_list_screen.dart`), add a muted contextual label `Session Type` directly above the mode-toggle row.
2. [ ] Update toggle-row layout so both segmented buttons share available width and always display full labels without truncation (`Custom Routine` must never clip/ellipsis).
3. [ ] Ensure text can wrap/fit safely under constrained width while preserving current modal width (no sheet width increase).
4. [ ] Increase selected/unselected contrast in dark modal context:
5. [ ] Active segment is clearly highlighted with stronger fill/background emphasis.
6. [ ] Inactive segment has a clearly visible but muted outline and reduced emphasis.
7. [ ] Keep color usage aligned with existing design tokens/theme system (`AppTheme` / current semantic colors), avoiding hardcoded one-off values when equivalents exist.
8. [ ] Verify both add and edit entry points render the same improved toggle since they share `_PlannedSessionForm`.

### Implementation Steps
1. [ ] Locate mode selector block in `_PlannedSessionForm` and insert `Session Type` label with subdued typography style used by nearby helper labels.
2. [ ] Adjust segmented control/button container constraints (e.g., expanded/flexible layout and padding) to guarantee full label rendering for both options.
3. [ ] Tune selected/unselected decoration (fill, border, and foreground) for clear visual separation on dark sheet background.
4. [ ] Run analyzer/tests affected by the file and ensure no behavior regressions.
5. [ ] Perform visual smoke check on both add and edit planned-session flows.

### Acceptance Criteria
- [ ] Mode toggle shows full `Free Training` and `Custom Routine` labels with no truncation or ellipsis at supported app widths.
- [ ] A muted `Session Type` label appears directly above the toggle row in the planned-session form.
- [ ] Active and inactive toggle states are clearly distinct in dark modal context.
- [ ] Inactive state uses visible muted outline; active state is unmistakably highlighted.
- [ ] Modal overall width remains unchanged.
- [ ] Existing form logic and field-swapping behavior are unchanged.
- [ ] Both add and edit flows reflect the same UI improvements via shared form.

### Files Affected
- lib/features/calendar/day_session_list_screen.dart
- test/ (only if an existing widget test is updated to assert label visibility/contrast semantics)

### Execution Note
- Phase 2 (Logic/UI) is approved to proceed.
- Runtime compatibility guardrail: implementation must remain repository-interface-driven so current web (`HiveWorkoutRepository`) and future native (`SqliteWorkoutRepository`) continue to work without storage-specific branching in UI/state.

## Progress (Iteration 5)
- [x] Add `Session Type` context label above mode toggle
- [x] Remove label truncation by fixing toggle row constraints
- [x] Improve selected vs unselected visual contrast
- [x] Verify add and edit flows share the updated UI
- [x] Run analyzer/tests and visual smoke check

## Feedback
[Leave empty until a specialist or reviewer adds notes]

- Iteration 5 copy requirement says keep button copy exactly `Free Training` and `Custom Routine`. Current implementation renders `Free\nTraining` in the button label, which changes the explicit copy token and should be reverted to the exact requested text.
- Iteration 5 implementation step requires analyzer/tests + visual smoke validation; staged progress still shows this item unchecked, so acceptance cannot be marked complete yet.

- Resolved: mode copy now uses exact `Free Training` / `Custom Routine` labels; widget coverage added for add and edit entry points and targeted tests are green.