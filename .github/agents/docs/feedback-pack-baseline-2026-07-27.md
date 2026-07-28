# 2026-07-27 Feedback-Pack Current-State Baseline

> **Scope:** Documentation-only source audit for PR 1. This page records what is implemented in `lib/` before PRs 2–8. Statements under **Scheduled change** are desired behavior from plans, not shipped behavior.

## Shipping Order

Execute the [2026-07-27 feedback-pack queue](../plans/2026-07-27-00-feedback-pack-shipping-order.md) in numeric order before the pending 2026-07-13 plans:

1. PR 1 — documentation refresh (this baseline)
2. PR 2 — launch quality hotfix
3. PR 3 — isolated UI corrections
4. PR 4 — session screen controls
5. PR 5 — routine unsaved-changes guard
6. PR 6 — routine and session-entry navigation
7. PR 7 — exercise details view
8. PR 8 — exercise library

## Verified Current State vs Scheduled Change

| Area | Current source behavior on 2026-07-27 | Scheduled change (not current) |
|---|---|---|
| Startup | `StartupRoot` has only `_runningApp` and `_attemptInFlight`. While the first attempt is preparing, `_runningApp == null`, so `build` renders `StartupFailureScreen` with retry disabled/spinning. Success mounts the returned app; an exception leaves the same failure surface available for Retry. Preparation and genuine failure are therefore visually conflated. | [PR 2](../plans/2026-07-27-02-pr2-launch-quality-hotfix-plan.md) introduces distinct preparing, succeeded, and genuinely failed states; preparation is neutral and success never passes through failure content. |
| Detail gestures | Workout detail and routine detail both use screen-level drag handlers at an absolute primary-velocity threshold of `200`: right/left moves previous/next set; up/down moves next/previous exercise. Number scrollers have their own drag handling. | PR 2 removes both horizontal set and vertical exercise swipe navigation without replacement, preserving explicit controls and number-scroller sensitivity. |
| Routine exits | Routine header back and bottom Cancel call `_discardAndPop`; system back calls `_handleWillPop`. At list level these paths clear working routine state and leave without checking for unsaved changes. Detail-level system back first returns to the list. | [PR 5](../plans/2026-07-27-05-pr5-routine-unsaved-changes-guard-plan.md) adds one baseline comparison and one shared confirmation for header back, system back, and Cancel. |
| Routine cards and start | A routine card body immediately runs `_startRoutine`; its overflow menu contains Edit and Delete. Starting builds a manifest, creates and populates a routine session, and lands directly on `WorkoutSessionScreen`. | [PR 6](../plans/2026-07-27-06-pr6-routine-session-entry-navigation-plan.md) makes the card body open the editor, adds a distinct start control, removes overflow, and moves confirmed delete to the routine header. |
| Empty session entry | Modality and Free Training starts already push `WorkoutSessionScreen`, but first load of an empty non-edit session schedules `_addExercise`, so the picker auto-opens. The underlying empty list has Add Exercise and Add Block controls, currently filled vs outlined rather than equally weighted. Routine-populated sessions bypass this empty path. | PR 6 removes auto-open and exposes equally weighted Add Exercise/Add Block choices on the neutral empty session. Block-header add remains direct to the picker. |
| Rest | `EntryRest` persists start/end wall-clock timestamps. The most recent open rest renders as a non-interactive chip and closes when logging the next entry or starting an effort timer. There is no pause/resume state or whole-chip tap behavior. | [PR 4](../plans/2026-07-27-04-pr4-session-screen-controls-plan.md) adds persisted, reload-safe pause/resume and distinct not-started/running/stopped presentation. |
| Nutrition target entry | `NutritionScreen` uses the icon-only `edit_targets_icon` tune button in the TODAY header; it opens the existing `NutritionTargetScreen`. | [PR 3](../plans/2026-07-27-03-pr3-isolated-ui-corrections-plan.md) replaces it with a state-aware labelled control while keeping the destination unchanged. |
| Exercise ownership | `Exercise.ownerUserId` is nullable. Custom creation stamps the hard-coded value `'user-1'`; bundled rows leave it null, but no production code treats that distinction as a supported custom-exercise identity contract. There is no `isCustom` field. | PR 7 requires reliable custom markers; PR 8 may add/migrate a durable ownership contract and must not assume legacy nullability is sufficient without verification. |
| Maintenance sheet | The shipped home logo/drag interaction opens `HomeScreen._buildMaintenanceGrid`: Calendar, Stats, Profile, Settings. The separate five-item `HubSheet` (including Nutrition) is built/tested but not instantiated. No Exercise Library destination exists. | [PR 8](../plans/2026-07-27-08-pr8-exercise-library-plan.md) adds Exercise Library to the actual wired home maintenance sheet, not the home tile grid or unwired `HubSheet`. |

## Audit Boundary

- Source inspected: startup root and bootstrap, home/session/routine/nutrition screens, exercise model/library, rest state and overlay, and both maintenance-sheet implementations.
- No application source is changed by PR 1.
- Current feature docs remain authoritative for details; this page is the explicit boundary between the 2026-07-27 source baseline and downstream desired contracts.

---

> **Doc freshness** — Reconciled against `lib/` on 2026-07-27. Source wins on disagreement.
