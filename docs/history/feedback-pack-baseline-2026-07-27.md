# 2026-07-27 Feedback-Pack Current-State Baseline

> **HISTORY — DO NOT TREAT AS CURRENT STATE.**
> This document is the frozen record of what `lib/` looked like on
> **2026-07-27**, immediately before the 2026-07-27 feedback pack (PRs 2–8) was
> implemented. It is preserved here for the audit trail only.
> **Its contents were accurate as of 2026-07-27 and are no longer accurate.**
> PRs 2, 4, 5 and 6 have since shipped, so the "Current source behavior" column
> below describes behaviour that has been **removed**, and the "Scheduled
> change" column describes behaviour that has since **shipped**.
> **Current source of truth:** the `lib/` tree, and the feature docs in
> [`.github/agents/docs/`](../README.md). Where this page and either disagree,
> this page is wrong.
> **Frozen:** 2026-07-27 (no claim in this baseline was modified when it was
> relocated to `history/`; it is read-only history).

---

## Baseline State vs Scheduled Change, as recorded on 2026-07-27

| Area | Current source behavior on 2026-07-27 | Scheduled change (not current) |
|---|---|---|
| Startup | `StartupRoot` has only `_runningApp` and `_attemptInFlight`. While the first attempt is preparing, `_runningApp == null`, so `build` renders `StartupFailureScreen` with retry disabled/spinning. Success mounts the returned app; an exception leaves the same failure surface available for Retry. Preparation and genuine failure are therefore visually conflated. | [PR 2](../plans/2026-07-27-02-pr2-launch-quality-hotfix-plan.md) introduces distinct preparing, succeeded, and genuinely failed states; preparation is neutral and success never passes through failure content. |
| Detail gestures | Workout detail and routine detail both use screen-level drag handlers at an absolute primary-velocity threshold of `200`: right/left moves previous/next set; up/down moves next/previous exercise. Number scrollers have their own drag handling. | PR 2 removes both horizontal set and vertical exercise swipe navigation without replacement, preserving explicit controls and number-scroller sensitivity. |
| Routine exits | Routine header back and bottom Cancel call `_discardAndPop`; system back calls `_handleWillPop`. At list level these paths clear working routine state and leave without checking for unsaved changes. Detail-level system back first returns to the list. | [PR 5](../plans/2026-07-27-05-pr5-routine-unsaved-changes-guard-plan.md) adds one baseline comparison and one shared confirmation for header back, system back, and Cancel. |
| Routine cards and start | A routine card body immediately runs `_startRoutine`; its overflow menu contains Edit and Delete. Starting builds a manifest, creates and populates a routine session, and lands directly on `WorkoutSessionScreen`. | [PR 6](../plans/2026-07-27-06-pr6-routine-session-entry-navigation-plan.md) makes the card body open the editor, adds a distinct start control, removes overflow, and moves confirmed delete to the routine header. **S-006 follow-up (2026-07-28):** the start control is a bare `Icons.play_arrow` glyph (no text label, accent colour, no fill or border, 48 dp hit target) instead of a 96-dp filled "Start" button; the "Demo" pill moves off the title line onto the metadata line. Between these two changes routine names of typical length render in full on a 320-dp viewport. **S-007 follow-up (2026-07-28):** the start control tap region is bumped to 56 dp (still smaller than the row body, no scaling of the visible glyph), the row body's right edge sits flush with the start control's left edge so there is no dead zone, and the Demo badge is pinned to the right edge of the metadata line via a `Stack` so its horizontal position is stable across every row regardless of date text length — user rows render the date full-width with no reserved gap. **S-008 follow-up (2026-07-28, design pivot):** the Demo badge moves BACK from the metadata line onto the title row, vertically centred with the title text. The title text sits in an `Expanded` (FlexFit.tight) so the badge's right edge is pinned to the title row's right edge regardless of routine-name length. The metadata line returns to a simple `Text` widget — no Stack, no Positioned, no reserved space. S-008 reverts the metadata-line placement because the start control is now small enough (56-dp tap region around a 28-dp glyph) for the title row to host the badge without crowding the routine name. |
| Empty session entry | Modality and Free Training starts already push `WorkoutSessionScreen`, but first load of an empty non-edit session schedules `_addExercise`, so the picker auto-opens. The underlying empty list has Add Exercise and Add Block controls, currently filled vs outlined rather than equally weighted. Routine-populated sessions bypass this empty path. | PR 6 removes auto-open and exposes equally weighted Add Exercise/Add Block choices on the neutral empty session. Block-header add remains direct to the picker. **S-005 contract** (follow-up): Add Exercise and Add Block are always-secondary OutlinedButtons regardless of session contents — adding a block or an exercise must never flip Add Exercise to primary; the bottom Finish Workout CTA is the only FilledButton in the session screen. **S-006 contract** (follow-up): on the `MyRoutinesScreen` card, the start control is a bare play glyph with no text label — the same secondary-button discipline now applies to the routine list. |
| Rest | `EntryRest` persists start/end wall-clock timestamps. The most recent open rest renders as a non-interactive chip and closes when logging the next entry or starting an effort timer. There is no pause/resume state or whole-chip tap behavior. | [PR 4](../plans/2026-07-27-04-pr4-session-screen-controls-plan.md) adds persisted, reload-safe pause/resume and distinct not-started/running/stopped presentation. |
| Nutrition target entry | `NutritionScreen` uses the icon-only `edit_targets_icon` tune button in the TODAY header; it opens the existing `NutritionTargetScreen`. | [PR 3](../plans/2026-07-27-03-pr3-isolated-ui-corrections-plan.md) replaces it with a state-aware labelled control while keeping the destination unchanged. |
| Exercise ownership | `Exercise.ownerUserId` is nullable. Custom creation stamps the hard-coded value `'user-1'`; bundled rows leave it null, but no production code treats that distinction as a supported custom-exercise identity contract. There is no `isCustom` field. | **PR 7 (shipped):** `Exercise.isCustomExercise` (in `lib/core/utils/exercise_helpers.dart`) commits to `ownerUserId != null` as the canonical custom marker. PR 8 reuses the contract. |
| Maintenance sheet | The shipped home logo/drag interaction opens `HomeScreen._buildMaintenanceGrid`: Calendar, Stats, Profile, Settings. The separate five-item `HubSheet` (including Nutrition) is built/tested but not instantiated. No Exercise Library destination exists. | [PR 8](../plans/2026-07-27-08-pr8-exercise-library-plan.md) adds Exercise Library to the actual wired home maintenance sheet, not the home tile grid or unwired `HubSheet`. |

## Audit Boundary

- Source inspected: startup root and bootstrap, home/session/routine/nutrition screens, exercise model/library, rest state and overlay, and both maintenance-sheet implementations.
- No application source is changed by PR 1.
- Current feature docs remain authoritative for details; this page is the explicit boundary between the 2026-07-27 source baseline and downstream desired contracts.

---

> **Doc freshness** — Reconciled against `lib/` on 2026-07-27. Source wins on disagreement.
