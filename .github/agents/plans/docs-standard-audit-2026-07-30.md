# Documentation Audit against the Documentation Standard — 2026-07-30

**Status: PROPOSAL FOR HUMAN REVIEW. Nothing here has been acted on.**

This file audits every document under `.github/agents/docs/` against
[`documentation_standard.md`](../docs/documentation_standard.md). It is a decision
record, not a work order. No document was modified, no test was written, and no
application source was touched to produce it.

It lives **outside** `.github/agents/docs/` deliberately: it is a review
artefact, not reference documentation, and should not be indexed and served to
agents as though it were.

## How to review this

Each item is individually numbered so you can respond item-by-item ("3 remove,
4 preserve, 7 disagree"). Items are grouped by source document.

Each item records:

- **Section** — the heading it appears under
- **Claim** — what the document asserts
- **Category** — which prohibited category of the standard it falls under
- **Verified?** — whether a test currently covers the claim
- **Recommendation** — `REMOVE` or `PRESERVE AS TEST`

`PRESERVE AS TEST` means the claim describes real, current, valuable behaviour
that no test guards. Deleting it would lose institutional knowledge, so it
should become a test before the prose goes.

`REMOVE` means the claim is stale, already verified elsewhere, or is
presentation detail the source already owns.

**Part A is the highest-risk section.** Those claims describe functionality that
no longer exists in the codebase at all. An agent planning against them will
produce work against a system that isn't there — this has already happened.

---

# PART A — Claims describing functionality that no longer exists

Every item in this part was checked against `lib/` on 2026-07-30. These are
**not** stylistic violations; they are false statements presented as current
fact.

A recurring root cause: the 2026-07-27 feedback pack (PRs 2, 4, 5, 6) shipped,
but the documents that described the pre-PR state were never updated. Several
docs carry "Scheduled, not current" annotations that have now **inverted** —
they label shipped behaviour as future and removed behaviour as current.

## A.1 — `modality_based_exercise_ui.md`

### 1. Screen-level swipe gesture table
- **Section:** "6. Set Navigation and Control" → "Current Screen-Level Swipe Gestures (workout detail view)"
- **Claim:** The detail view uses `primaryVelocity` with an absolute threshold of `200`; horizontal right/left navigates previous/next set, vertical up/down navigates next/previous exercise; routine setup detail mirrors the same four gestures.
- **Category:** §3.3 gesture inventory, §3.4 numeric value, and **absent functionality**
- **Verified?** Yes — inverted. `test/pr2_launch_quality_hotfix_test.dart` group `S-003` asserts these gestures are **gone** from both `WorkoutSessionScreen` and `RoutineSetupScreen` detail views. `grep -rn "primaryVelocity" lib/` returns **zero** hits; there are no drag handlers in `lib/features/session/` or `lib/features/routine/`.
- **Recommendation:** `REMOVE`. A passing test already asserts the opposite. This is the single most dangerous entry in the docs set.

### 2. "Scheduled, not current" note on gesture removal
- **Section:** same section, immediately below item 1
- **Claim:** "feedback-pack PR 2 removes all four screen-level navigation gestures… " (framed as future work)
- **Category:** §3.7 scheduled-change annotation, **inverted**
- **Verified?** Yes — PR 2 shipped. Covered by `pr2_launch_quality_hotfix_test.dart`.
- **Recommendation:** `REMOVE` together with item 1.

### 3. `InlineMetricEditor` swipe interaction and sensitivity table
- **Section:** "Core UX Patterns → 1. InlineMetricEditor (Scrollable Value Adjustment)"
- **Claim:** "Swipe up → increase value / Swipe down → decrease value / No tap/keyboard required (eyes-free operation)", plus a five-row "Sensitivity Tuning" table of increments per 10 px drag.
- **Category:** §3.3 gesture inventory, §3.4 numeric values, and **absent functionality**
- **Verified?** No test asserts drag behaviour on this widget, because it has none. `lib/widgets/session/inline_metric_editor.dart` contains no drag handler at all — the number is a tap target that opens `showMetricEditPopup`. `widget_catalog/session_widgets.md` documents the real model ("Number tap is the sole value-change mechanism"), directly contradicting this page.
- **Recommendation:** `REMOVE`. The interaction model is documented correctly in the widget catalog; this page describes a widget that was replaced.

### 4. Rest chip described as non-interactive
- **Section:** "5. Rest Timer Overlay → Behavior"
- **Claim:** "The current chip is display-only: it has no tap handler and `EntryRest` has no paused/stopped state", followed by a "Scheduled, not current" note that PR 4 *will* add pause/resume.
- **Category:** §3.7 scheduled-change annotation, **inverted**
- **Verified?** Yes — inverted. PR 4 shipped: `EntryRest` carries `restIsPaused` / `restPausedAtMs` / `restPausedDurationMs`, `WorkoutState` exposes `pauseRest` / `resumeRest` / `isRestPaused`, and `test/pr4_session_controls_test.dart` group `Rest tile — UI state mirroring` covers it. `rest_tracking.md` documents the shipped behaviour, so the two docs contradict each other.
- **Recommendation:** `REMOVE`. `rest_tracking.md` is the correct owner.

### 5. Empty-state picker auto-open
- **Section:** "Edge Cases and Error Handling → Empty State"
- **Claim:** "after an empty non-edit session loads, `_shouldAutoOpenPicker()` schedules `_addExercise()`, so `ExercisePickerScreen` opens automatically", plus a "Scheduled, not current" note that PR 6 *will* remove it.
- **Category:** §3.7 scheduled-change annotation, **inverted**
- **Verified?** Yes — inverted. `lib/features/session/workout_session_screen.dart:1408` is `bool _shouldAutoOpenPicker() => false;` with a `PR 6: no-op` comment. `test/pr6_routine_session_entry_navigation_test.dart` group `S-003 empty session no longer auto-opens picker` asserts the removal.
- **Recommendation:** `REMOVE`.

### 6. Stopwatch reuse claim
- **Section:** "Performance Optimizations → State Locality"
- **Claim:** "Stopwatch instances reused across pause/resume cycles"
- **Category:** **absent functionality**
- **Verified?** No test, because there is nothing to test. The same document states four sections earlier that "There is no `Stopwatch`-based elapsed counter in the active source." The document contradicts itself.
- **Recommendation:** `REMOVE`.

### 7. Stale file line count
- **Section:** "Developer Notes → Code Organization"
- **Claim:** "`workout_session_screen.dart` (1412 lines)" and "`inline_metric_editor.dart` (200 lines)"
- **Category:** §3.4 numeric value defined elsewhere, §3.5 copied implementation content
- **Verified?** No. Actual: 1731 lines. The file was also split into part files since this was written.
- **Recommendation:** `REMOVE`. Line counts should never appear in prose.

### 8. "Planned Features → Round Bell"
- **Section:** "Future Enhancements → Planned Features"
- **Claim:** Round Bell (audio/haptic alert when countdown reaches 0:00) is a planned future feature.
- **Category:** §3.6 roadmap section, **inverted**
- **Verified?** Shipped. The same document states at "`effortKind == 'round'`" that the "configured effort-timer sound fires at 0:00", and `theme_and_settings.md` documents the `effortTimerSound` preference and `TimerAlertService.fireEffortTimerAlert`.
- **Recommendation:** `REMOVE` the whole "Future Enhancements" section (see item 42).

## A.2 — `my_routines.md`

### 9. Overflow-menu edit flow
- **Section:** "User Workflows → 4. Editing a Routine"
- **Claim:** "MyRoutinesScreen → Tap ⋮ menu on routine card → 'Edit' → RoutineSetupScreen"
- **Category:** §3.1 step-by-step flow, **absent functionality**
- **Verified?** Yes — inverted. `grep -n "PopupMenuButton" lib/features/routine/my_routines_screen.dart` returns nothing; the only `PopupMenuButton`s live in `routine_setup_screen.dart`. `test/pr6_routine_session_entry_navigation_test.dart` group `S-001 routine card intent split` asserts the card body opens the editor and there is no overflow menu.
- **Recommendation:** `REMOVE`. Note the document contradicts itself — the PR 6 contract block two paragraphs above says "The card never renders an overflow menu."

### 10. Card-tap-starts-session and overflow menu bullets
- **Section:** "UI Architecture → MyRoutinesScreen"
- **Claim:** "Tap card → starts routine as session" and "⋮ menu → Edit or Delete"
- **Category:** §3.3 control inventory, **absent functionality**
- **Verified?** Yes — inverted, same test as item 9. Card body now opens the editor; a bare play glyph starts the session.
- **Recommendation:** `REMOVE`.

### 11. "No unsaved-changes prompt" claim
- **Section:** "UI Architecture → MyRoutinesScreen"
- **Claim:** "No current unsaved-changes prompt protects routine setup exits"
- **Category:** **absent functionality** (the absence itself is what no longer exists)
- **Verified?** Yes — inverted. PR 5 shipped: `_attemptExit` in `routine_setup_screen.dart:1045`, `RoutineSnapshot` baseline in `routine_state.dart`, covered by `test/routine_unsaved_changes_guard_test.dart` groups `S-001`/`S-002`/`S-003`.
- **Recommendation:** `REMOVE`. Actively dangerous — an agent could "add" a guard that already exists.

### 12–14. Routine-detail swipe gestures (three separate occurrences)
- **Sections:** (12) "UI Architecture → MyRoutinesScreen" bullet; (13) "RoutineSetupScreen → Detail View → Current screen-level swipe gestures"; (14) the prose paragraph under "4. Editing a Routine"
- **Claim:** Routine detail navigates sets/exercises with horizontal/vertical swipes at a `200` velocity threshold; "Feedback-pack PR 2 removes these handlers without replacement".
- **Category:** §3.3 gesture inventory, §3.4 numeric value, §3.7 scheduled-change, **absent functionality**
- **Verified?** Yes — inverted. `test/pr2_launch_quality_hotfix_test.dart` group `RoutineSetupScreen detail view — swipe removal (S-003)`.
- **Recommendation:** `REMOVE` all three.

### 15. "Phase 2 → Segment grouping" roadmap item
- **Section:** "Future Enhancements → Phase 2"
- **Claim:** "Segment grouping: Split routine into Warm-up / Main / Cool-down segments" is future work.
- **Category:** §3.6 roadmap section, **inverted**
- **Verified?** Shipped. The same document's "Key Design Decisions → 2. Multiple Segments (Blocks) Per Routine" carries a 2026-07-26 correction stating the grouping shipped "with very nearly the labels the doc used as its example of what was deferred", and lists the five segment types.
- **Recommendation:** `REMOVE` the whole "Future Enhancements" section (see item 43).

## A.3 — `stats_screen.md`

### 16. An entire second, superseded copy of the document
- **Section:** everything from the second `## Navigation Entry Point` heading to the end (a complete v1.0 document, "Last Updated: April 11, 2026", appended below the v2.3 document)
- **Claim:** The screen "is organized into three sections"; it has an **ACTIVITY** 30-day session bar chart and a **REST TIME** multi-line chart; data loads via `getEntryRestsByModalityInDateRange`.
- **Category:** §3.8 duplicated/superseded document body, **absent functionality**
- **Verified?** No. `grep -n "ACTIVITY\|REST TIME\|_dayCounts" lib/features/stats/stats_screen.dart` returns **zero** hits. The real section headers are `ALL TIME`, `STRENGTH`, `CARDIO`, `HOW DID IT FEEL`, `NUTRITION` — five, not three. The v2.3 half of the same file says five. The file contradicts itself end-to-end.
- **Recommendation:** `REMOVE` the entire appended v1.0 body. This is the largest single block of false content in the docs set. *(Note: `getEntryRestsByModalityInDateRange` does still exist on the repository interface — the method survived, the screen section that used it did not. Worth confirming whether the method is now dead code; that is a source question, not a docs one.)*

### 17. Phantom chart constant
- **Section:** "Key Constants (`ScrollableTrendChart`)"
- **Claim:** `kScrollableTrendPerPointWidth` = 48 px, "Fixed horizontal slot per plotted point"
- **Category:** §3.4 numeric value, **absent functionality**
- **Verified?** No. That constant does not exist. `scrollable_trend_chart.dart` declares `kScrollableTrendMaxVisiblePoints = 8`, `kScrollableTrendMinPerPointWidth = 28.0`, `kScrollableTrendChartHeight = 120.0`, `kScrollableTrendPinnedAxisWidth`. The per-point width is *computed*, not fixed — as the same document's "Scrollable Charts" section correctly describes.
- **Recommendation:** `REMOVE` the table (all three rows restate values §3.4 already prohibits).

### 18. Windowing table rows for absent surfaces
- **Section:** "Selection Window → What Is (and Isn't) Windowed"
- **Claim:** Rows for "30-day Activity bar chart" and "Rest Time chart" (both "No / Unchanged"). Also referenced in the prose above the table.
- **Category:** **absent functionality**
- **Verified?** No — these surfaces do not exist (see item 16).
- **Recommendation:** `REMOVE` both rows.

## A.4 — `modality_tracking.md`

### 19. "Recommended vs Others" picker partitioning
- **Sections:** "Data Layer → Exercise Ranking Logic"; "UI Layer → Exercise Picker with Ranking" (with code block); "Manual Test Scenarios" items 2 and 5
- **Claim:** The picker partitions exercises into a "Recommended" section and an "Others" section and renders section headers.
- **Category:** §3.5 copied implementation content, **absent functionality**
- **Verified?** No. `exercise_ranking.md` states plainly: "that partitioning has been removed and the list is displayed in the repository's sorted order." Two docs disagree; the source agrees with `exercise_ranking.md`.
- **Recommendation:** `REMOVE`.

### 20. `SqliteWorkoutRepository` as the native runtime
- **Sections:** "Web Compatibility Strategy → Future SQLite Repository (Native — Planned)"; "Deployment Notes → Environment Requirements" ("Web: MockWorkoutRepository / iOS/Android: SqliteWorkoutRepository (future)"); "Migration Path"; "Acceptance Criteria" ("Schema ready for native (SqliteWorkoutRepository)")
- **Category:** §3.6 roadmap section, **absent functionality**
- **Verified?** No. `CLAUDE.md` and `db_integration.md` both record that the SQLite runtime was **retired**: `sqflite` is gone, the datasource files were deleted, and `HiveWorkoutRepository` is the runtime on every platform including web. `MockWorkoutRepository` is a test/dev implementation, not the web runtime.
- **Recommendation:** `REMOVE`. This misdescribes the persistence architecture, which is a Tier-1 planning input.

### 21. "Recommended for this workout" section
- **Section:** "User Workflows → 1. Structured Workout (Modality-Driven)"
- **Claim:** "System shows 'Recommended for this workout' section"
- **Category:** §3.1 step-by-step flow, **absent functionality**
- **Verified?** No — same removal as item 19.
- **Recommendation:** `REMOVE`.

## A.5 — `feedback-pack-baseline-2026-07-27.md`

### 22. The whole "Verified Current State vs Scheduled Change" table
- **Section:** "Verified Current State vs Scheduled Change"
- **Claim:** The left column states current source behaviour as of 2026-07-27 for Startup, Detail gestures, Routine exits, Routine cards and start, Empty session entry, Rest, Nutrition target entry, Exercise ownership, and Maintenance sheet. The right column states what PRs 2–8 *will* change.
- **Category:** §3.7 scheduled-change annotation (the document's entire purpose), **absent functionality** for five of nine rows
- **Verified?** Inverted for the Detail-gestures, Routine-exits, Routine-cards, Empty-session, and Rest rows — those PRs have all shipped and are covered by `pr2_launch_quality_hotfix_test.dart`, `pr4_session_controls_test.dart`, `routine_unsaved_changes_guard_test.dart`, and `pr6_routine_session_entry_navigation_test.dart`.
- **Recommendation:** `REMOVE` the document entirely, or relocate it to `history/` with a `HISTORY` banner and its freeze date. It is a point-in-time delivery-planning artefact — exactly what §3.6/§3.7 say belongs in `plans/`. It is currently linked from `README.md` as a *current* reference, which is the harmful part.

## A.6 — `profile_and_measurements.md` and `theme_and_settings.md`

### 23. Hub sheet as a live entry point (profile doc)
- **Section:** "Entry Points"
- **Claim:** "`HomeScreen` maintenance sheet (**and the home-screen Hub sheet surfaced from the logo tap**)" routes to Profile / Stats / Settings.
- **Category:** **absent functionality**
- **Verified?** No. `HubSheet` is never instantiated — `grep -rn "HubSheet(" lib/` finds only its own constructor. `navigation_and_screens.md` flags this explicitly under "Unresolved: two hub implementations". The logo tap opens `HomeScreen._buildMaintenanceGrid`, not `HubSheet`.
- **Recommendation:** `REMOVE` the parenthetical. Keep the maintenance-sheet entry point.

### 24. Hub sheet as a live entry point (settings doc)
- **Sections:** "Settings Screen" ("also reachable from the home-screen Hub sheet") and "Version Footer" ("and via `HubSheet` for the secondary access path")
- **Category:** **absent functionality**
- **Verified?** No — same as item 23.
- **Recommendation:** `REMOVE` both.

## A.7 — `app_philosophy.md`

### 25. Four-item maintenance sheet
- **Section:** "8. Home Screen Structure → Maintenance Sheet"
- **Claim:** "The production sheet renders **four** items, in this order: Calendar, Stats, Profile, Settings" (itself a 2026-07-26 correction).
- **Category:** §3.3 control inventory, **absent functionality** (understates by one)
- **Verified?** No. `_buildMaintenanceGrid` in `home_screen.dart` now renders **five**: Profile, Stats, Calendar, Settings, **Exercise Library** (PR 8). `navigation_and_screens.md` and `widget_catalog/home_screen.md` both say five. This doc was corrected once and has already drifted again.
- **Recommendation:** `REMOVE` the item table. Under §2.1 the sheet's *existence and role* is permitted; its *inventory* is not.

## A.8 — `db_integration.md`

### 26. Migrations located in `lib/data/datasources/`
- **Section:** "Overview"
- **Claim:** "SQL schema assets + migrations: maintained in `scripts/` and `lib/data/datasources/`"
- **Category:** **absent functionality**
- **Verified?** No. `lib/data/datasources/` contains only `food_catalog_loader.dart`. The same document's "SQLite Schema Versioning" section carries a 2026-07-26 correction stating `migrations.dart` was deleted. The Overview was not updated to match.
- **Recommendation:** `REMOVE` the `lib/data/datasources/` reference from the Overview.

### 27. Dangling cross-reference
- **Section:** "Food Library & Catalog → Backwards compatibility for legacy installs"
- **Claim:** "(see the Hive Migration Keys section above)"
- **Category:** **absent** (the target section does not exist in this document)
- **Verified?** No. There is no "Hive Migration Keys" section; it was replaced by "Data-migration version sequence (July 2026)".
- **Recommendation:** `REMOVE` or repoint.

## A.9 — `README.md` and `feedback-pack-baseline-2026-07-27.md`

### 116. Link to a shipping-order plan that does not exist
- **Sections:** `README.md` → "Feedback-pack baseline — 2026-07-27" banner and the "Shared Conventions" table; `feedback-pack-baseline-2026-07-27.md` → "Shipping Order"
- **Claim:** Both link to `../plans/2026-07-27-00-feedback-pack-shipping-order.md`, and `README.md` states that "the linked shipping order **takes precedence over** the pending 2026-07-13 plans".
- **Category:** **absent functionality** (broken reference), §3.6 roadmap
- **Verified?** Yes, and **currently failing.** `test/docs_indexing_contract_test.dart` (`every relative link resolves to a file that exists`) fails on exactly these two links. `.github/agents/plans/` contains `2026-07-27-01-…` through `-08-…`; there is no `-00-` shipping order.
- **Recommendation:** `REMOVE`. **This is a pre-existing failing test, not caused by this task** — see D.6. An agent told that a precedence-setting document exists, and finding nothing there, has no way to resolve the conflict between the 2026-07-27 and 2026-07-13 plan sets.

## A.10 — `session_summary.md`

### 28. Repository compatibility claim
- **Section:** "Technical Architecture → Service: SessionSummaryService → Repository compatibility"
- **Claim:** "Works with both `HiveWorkoutRepository` and `SqliteWorkoutRepository`"
- **Category:** **absent functionality**
- **Verified?** No. `SqliteWorkoutRepository` does not exist in the tree.
- **Recommendation:** `REMOVE`. The real invariant — "depends on the `WorkoutRepository` interface only" — is already stated on the line above and is worth keeping under §2.3.

---

# PART B — Standard violations (content is current, but prohibited)

These claims are not necessarily false. They violate the standard because they
are behaviour, presentation, gestures, restated numbers, copied code, or
roadmap — content that will go stale silently and that the source or a test
already owns.

## B.1 — `modality_based_exercise_ui.md`

This document is the least conformant in the set. It is a UX specification, not
a reference document, and roughly 70% of its body is prohibited content.

| # | Section | Claim | Category | Verified? | Rec. |
|---|---|---|---|---|---|
| 29 | Effort Kinds (UI Rendering Modes) | Table of primary metrics, controls, and progress labels per effort kind | §3.2 presentation, §3.3 control inventory | Partly — `test/screen_widget_test.dart`, emphasis-tier tests | REMOVE (keep the effort-kind *vocabulary* under §2.4) |
| 30 | Metric Widget Rendering (all four `effortKind` subsections) | Dart `Column(children: [...])` blocks plus "**User Flow**: Swipe up/down… → Tap 'Log Set'" walkthroughs | §3.1 flow, §3.5 copied code | No | REMOVE |
| 31 | 3. Set Progress Visualization | Copied `switch (effortKind)` block; "Hollow dots: Future sets / Filled dots: Completed / Larger dot: Current set (50% opacity)" | §3.2 presentation, §3.5 copied code | No | REMOVE |
| 32 | 4. Previous Set Stats | Example output strings per effort kind; "Hidden when current set is the first set" | §3.2 presentation | No | **PRESERVE AS TEST** — the "hidden on first set" rule is a real behavioural contract worth a test |
| 33 | 5. Rest Timer Overlay → Visual Design | Copied `Container(decoration: BoxDecoration(...))` block with radius, icon, font sizes | §3.2 presentation, §3.5 copied code | No | REMOVE |
| 34 | 6. Set Navigation and Control | Two control-inventory tables (Set Progress Row, Action Row) with icons and positions | §3.3 control inventory, §3.2 presentation | Partly — `test/session_toolbar_rework_test.dart` | REMOVE |
| 35 | Edge Cases → Set Skip vs Delete | Minus icon swaps to `Icons.delete_outline` when one set remains; tooltip changes to "Remove exercise" | §3.2 presentation | Unclear — worth checking `session_detail_set_count_test.dart` | **PRESERVE AS TEST** — the *rule* (last-set removal deletes the exercise and needs stronger confirmation) is a genuine safety invariant; the icon detail is not |
| 36 | Edge Cases → Modality Change Warning | Verbatim dialog copy and button labels | §3.2 presentation | No | **PRESERVE AS TEST** — that a confirmation is required is an invariant; the copy is not |
| 37 | Responsive Design Considerations | Touch-target sizes, a four-row type-hierarchy table (72 pt / 12 pt / 16 pt / 12 pt), colour-semantics list, dark-mode code block | §3.2 presentation, §3.4 numerics, §3.5 copied code | No | REMOVE — `design_system.md` owns this |
| 38 | Performance Optimizations → Timer Update Frequency | 1-second intervals for session / effort / rest timers | §3.4 numeric | No | REMOVE |
| 39 | Session Finalization → Finish Workout Flow | Four-step numbered shutdown sequence | §3.1 flow | Yes — `test/session_finish_timers_test.dart` | REMOVE and replace with a pointer (§4.2) |
| 40 | Edit Mode — Session Duration Editing | "the Session Time chip gains a tinted border, an edit icon, and becomes tappable" | §3.2 presentation, §3.3 control inventory | Yes — `test/session_edit_duration_test.dart` | REMOVE |
| 41 | Unsaved Changes Dialog | Trigger table plus dialog layout (close icon, outlined Discard, filled Save) | §3.2 presentation | Yes — `test/unsaved_changes_dialog_test.dart` | REMOVE, keep the pointer |
| 42 | Future Enhancements | Six "Planned Features" + four "Accessibility Improvements" | §3.6 roadmap | n/a | REMOVE (see item 8) |
| 43 | Developer Notes → Testing Strategy | Lists which tests *should* exist, by category | §3.6 roadmap-adjacent | n/a | REMOVE — §4.2 requires pointing at tests that exist, not describing tests that might |
| 44 | Conclusion | "Touch-Optimized: **Swipe gestures** and large targets suit workout environments" | §3.3 gesture inventory, **stale** | Inverted (see item 1) | REMOVE |

**Worth keeping from this document** (all §2.2 rationale or §2.3 invariants):
the Business Context / Problem / Solution framing; the "Timer State Management"
explanation of *why* elapsed time is wall-clock-derived rather than
`Stopwatch`-based; the Round state machine and its terminal-state invariant;
the "Immediate Persistence" rationale; and the Common Pitfalls list (timer key
format, round persistence going through `RoundInstance`).

## B.2 — `my_routines.md`

| # | Section | Claim | Category | Verified? | Rec. |
|---|---|---|---|---|---|
| 45 | Header PR-6 note (top of file, ~40 lines) | S-006/S-007/S-008 contracts: 56 dp tap region, 28 dp glyph, 320 dp viewport, badge placement reverted twice | §3.2 presentation, §3.4 numerics, §3.7 scheduled-change | Yes — `pr6_routine_session_entry_navigation_test.dart` groups S-006/S-007/S-008 | REMOVE — a fully-tested design iteration log at the top of a reference doc |
| 46 | User Workflows 1, 2, 3, 5 | Numbered `→`-arrow walkthroughs for accessing, creating, starting, and deleting routines | §3.1 flow | Partly | REMOVE 1/2/3. **PRESERVE AS TEST** for 5: "completed sessions, their `routineTemplateId`, observations, rest records and PRs are preserved when a template is deleted" is a real data-integrity invariant (`pr6…_test.dart` group `S-002 routine delete preserves history` may already cover it — confirm before removing) |
| 47 | UI Architecture → RoutineSetupScreen (List + Detail View) | Control inventories: drag handles, ⋮ menus, (+) in bottom-right corner, Cancel/Save buttons, set dots | §3.3 control inventory, §3.2 presentation | No | REMOVE |
| 48 | Smart Defaults for Targets | "set: 10 reps, 0 weight; round: 180 seconds (3 min), 1 round; drill: 0.0 extra weight" | §3.4 numeric values defined in `effort_defaults.dart` / `workout_constants.dart` | No | **PRESERVE AS TEST** — the *carry-forward rule* ("new sets auto-fill from the previous set") is real behaviour with no test I could find. Test the rule; drop the literals. |
| 49 | Technical Architecture → Model Fields | Three full field tables for `WorkoutTemplate` / `TemplateEffort` / `TemplateTarget` | §3.5 copied implementation content | n/a | REMOVE — `data_models.md` owns these, and this copy has already drifted (`targetMax`/`targetText` marked "unused currently") |
| 50 | Database Schema (SQLite) | ASCII FK tree copied from the schema file | §3.5 copied content | Yes — `test/db_seed_test.dart` executes the real schema | REMOVE |
| 51 | Home Screen Integration → Tile Configuration | Copied `HomeTileConfig(...)` block with hex gradient colours | §3.2 presentation, §3.5 copied code | No | REMOVE |
| 52 | Future Enhancements (Phase 2 + Phase 3) | Nine unbuilt ideas | §3.6 roadmap | n/a | REMOVE (see item 15) |
| 53 | Architecture Evolution → Phase 1 | Dated refactor narrative with ✅ benefit checklist | §3.6-adjacent changelog | n/a | REMOVE — but **PRESERVE the rationale**: "`RoutineState` must not depend on `WorkoutState`; session creation goes through `RoutineSessionService`" is a §2.3 invariant worth stating plainly |

**Worth keeping:** the Template ↔ Session parallel table (§2.1 structure); the
five "Key Design Decisions" with their rationale (§2.2); the Focus Modality
inheritance rule (§2.3); the demo-routine namespacing and tombstone contract
(§2.3).

## B.3 — `design_system.md`

This document is *entirely* §3.2 presentation content by definition, which puts
it in an awkward position: it is a design system, and a design system's job is
to describe presentation.

**Recommended disposition — your call:** rather than gutting it, treat
`design_system.md` as a **named exception** in the standard, on the condition
that it is the *single* owner of presentation content and every other document
defers to it. That is close to true already, and the alternative (deleting it)
loses the only place where visual rationale lives.

If you accept that, these still need attention:

| # | Section | Claim | Category | Verified? | Rec. |
|---|---|---|---|---|---|
| 54 | Theme roster + per-theme token tables + "Phase 1B Tier Values" + Macro Chart Palette | ~40 hardcoded hex values restating `omni_theme.dart` | §3.4 numeric values defined elsewhere | Partly — `test/app_theme_reactive_test.dart`, `emphasis_tier_contract_test.dart` | REMOVE the values, keep the token *names* and their *roles*. The values belong to `omni_theme.dart` alone. |
| 55 | Macro Chart Palette → "Iteration 2 / Iteration 3" notes | Change-log narrative of how the donut evolved, with plan links | §3.6-adjacent, §3.7 | n/a | REMOVE — belongs in the plan |
| 56 | Buttons → OmniTheme Tokens | Code block restating nine token values (12.0, 8.0, 10.0, 56.0, 60.0, 16.0, 24.0, 112.0) | §3.4, §3.5 | No | REMOVE the values; keep the token names |
| 57 | Known Inconsistencies (To Resolve) | Two open TODOs | §3.6 roadmap | n/a | REMOVE — these are issues, not documentation |

**Worth keeping and genuinely excellent:** the "Minimum Friction" philosophy,
the Splash Screen Litmus Test, "Spacecraft Interior" / What We Are NOT, the
Shape Rule (MANDATORY) as a §2.3 invariant, the Bottom CTA width/anchor rule
with its forbidden-patterns list, and the naming-convention prefix table.

## B.4 — `stats_screen.md` (v2.3 portion)

| # | Section | Claim | Category | Verified? | Rec. |
|---|---|---|---|---|---|
| 58 | HOW DID IT FEEL → Chart | `barWidth: 2`, `radius: 3`, `strokeWidth: 1.5`, tick counts, "no glow shadow, no halo ring, no area fill" | §3.2 presentation, §3.4 numerics | Partly — `scrollable_trend_chart_test.dart`, `chart_axis_helper_test.dart` | REMOVE the styling; **PRESERVE AS TEST** the axis rule (fixed 1..5 range, exactly 5 integer ticks, no auto-scale) — that is a data-integrity invariant, not decoration |
| 59 | Key Constants (StatsProgressService) | Table restating `kTopLiftCount` 3, `kTopCardioCount` 2, `kRecentPRCount` 5, `kRecentTrainingDaysWindow` 14, `kTopExerciseRecencyDays` 30, `kNutritionTrendDays` 10 | §3.4 numeric values | Partly — `test/stats_progress_test.dart` | REMOVE the values; keep the constant names and what each *means* (§2.4 vocabulary) |
| 60 | Per-day math block | Copied summation pseudocode | §3.5 copied content | Partly | REMOVE; point at `StatsProgressService.computeNutritionTrend` |
| 61 | On-screen Window Label | Exact label strings (`"· Last 14 training days"`) | §3.2 presentation, §3.4 numeric | No | REMOVE |
| 62 | What Is Intentionally Not in v1 | "Those three remain deferred to post-launch iteration" | §3.6 roadmap | n/a | REMOVE the deferral framing; the *negative invariants* ("Stats has no time-range control") may stay under §2.3 |

**Worth keeping and among the best content in the set:** the per-exercise axis
rule (reps-axis vs weight-axis) and the bodyweight-inclusion rule with their
rationale; the "Source of truth (Stats ↔ toast ↔ Session Summary)" section
stating there is exactly one e1RM formula and one standing-best query — a
textbook §2.3 invariant that already names its guards; the Effort-Type Keying
rule; the Selection Window resolution rule; and "Why not fl_chart's built-in
scroll?" (§2.2 rationale).

## B.5 — `navigation_and_screens.md`

| # | Section | Claim | Category | Verified? | Rec. |
|---|---|---|---|---|---|
| 63 | Complete Screen Flow | ~85-line ASCII tree with inline PR/scenario annotations, gesture notes, and button labels | §3.1 flow, §3.3 control inventory | Partly | REMOVE the annotations; a *screen graph* (which screen reaches which) is legitimate §2.1 structure and should stay |
| 64 | Screen Inventory → `HomeScreen` row | A single ~1,100-word table cell describing gauge geometry, px padding, fill math, caption dash behaviour, and superseded widget history | §3.2 presentation, §3.4 numerics, §3.8 duplication (repeats `widget_catalog/home_screen.md` verbatim) | Yes — `home_nutrition_summary_card_test.dart` | REMOVE — reduce to one sentence naming the screen's responsibility |
| 65 | Screen Inventory → `NutritionScreen`, `AddFoodScreen`, `EditFoodScreen`, `ExerciseLibraryScreen`, `ExerciseLibraryDetailScreen`, `ExerciseDetailViewScreen` rows | Widget keys, button colours, 40×40 thumbnail sizes, tab-by-tab interaction descriptions | §3.2 presentation, §3.3 control inventory | Largely yes — `pr8_exercise_library_test.dart`, `pr7_exercise_details_view_test.dart`, `food_library_*_test.dart` | REMOVE — the inventory should say what each screen is *for*, one line each |
| 66 | Screen Inventory → `WorkoutSessionScreen` row | PR 4 Discard button styling, icon swap rules, rest-chip icons | §3.2 presentation | Yes — `pr4_session_controls_test.dart` | REMOVE |
| 67 | Active Session Resume Logic | Numbered cold-start dialog flow with button labels | §3.1 flow, §3.2 presentation | Yes — `test/interaction_flow_test.dart` | REMOVE, replace with pointer. **PRESERVE AS TEST** if not covered: "system back-dismiss preserves the stored session (no delete side effect)" is a genuine data-loss guard |
| 68 | Trailing PR 6 / S-005 note block | Shipped-PR contract restated at the bottom of the file | §3.7 | Yes | REMOVE |

**Worth keeping:** the Navigation Contract statement and architecture diagram;
the `StartupRoot` lifecycle model (`preparing`/`succeeded`/`failed` as disjoint
states) — a §2.3 invariant with real rationale; the Dependency Injection
pattern and Key Injection Rules; the **Non-Production Screens** table
(`ExerciseDetailScreen`, `MaintenancePlaceholderScreen`) — §2.1 structure that
prevents an agent from wiring into dead code; and the "Unresolved: two hub
implementations" flag, which is exactly how an unresolved question should be
documented.

## B.6 — Widget catalog part pages

`widget_catalog.md` (the index) is conformant — see Part C. The five part pages
are not.

| # | Document / Section | Claim | Category | Verified? | Rec. |
|---|---|---|---|---|---|
| 69 | `widget_catalog/home_screen.md` → `NutritionSummaryCard` "Behavior (S-100..S-106)" | ~50 lines of geometry, widget keys, px sizes, font weights, empty/over-budget rendering | §3.2 presentation, §3.4 numerics | Yes — `home_nutrition_summary_card_test.dart` | REMOVE the rendering detail. **PRESERVE AS TEST** the three-way empty-state distinction (both-axes-empty vs gauge-only-empty vs caption-empty-with-data, S-200/S-201/S-202) if not already covered — that is subtle, non-obvious product logic |
| 70 | `widget_catalog/home_screen.md` → `MacroDonutChart` | Angle convention, half-open interval hit-testing, `gapDegrees`, label fit test, in-band label initials | §3.2 presentation, §3.4 numerics | Partly | REMOVE the presentation. **PRESERVE the angle-convention paragraph as §2.2 rationale** — "the hit-test uses raw `atan2` with no offset because `Canvas.drawArc` also measures from +X" is exactly the kind of non-obvious reasoning that is expensive to rediscover |
| 71 | `widget_catalog/home_screen.md` → `EnergyTile`, `MaintenanceTile`, `CalorieRing`, `WaterTrackerControl` | Prop tables plus fill percentages, rim/shadow specs, icon names, px paddings, animation cycles | §3.2 presentation, §3.4 numerics, §3.5 (prop tables mirror constructors) | Partly | REMOVE the visual specs; prop tables are borderline §3.5 — recommend keeping *responsibility* only |
| 72 | `widget_catalog/session_widgets.md` → `MetricCrownWidget` | "Drag step sensitivity" table (5 rows), `44×60` touch target, `2π / 120px` rotation | §3.3 gesture inventory, §3.4 numerics | No — the widget is **never instantiated** anywhere in `lib/` | REMOVE. The doc honestly labels it "dormant", but "can be re-enabled without any other changes" is a §3.6 roadmap claim about dead code. Recommend a separate decision: delete the widget or wire it up. |
| 73 | `widget_catalog/session_widgets.md` → `PRToast` | `duration: 4.0 s`, `bottom: 150`, `size: 36`, `fontSize: 18.0`, plus a "plan vs source drift" note | §3.2 presentation, §3.4 numerics | Yes — `test/pr_toast_test.dart`, `in_session_pr_toast_test.dart` | REMOVE. **PRESERVE** the "no `action:` field — the user is never asked to dismiss" rule as a §2.3 invariant |
| 74 | `widget_catalog/feature_primitives.md` → `MeasurementSparkline` | ~20 lines of axis geometry: 60 dp container, 38 dp label column, 9 pt labels, 1.5 dp stroke, 2 dp dots, and a size-history changelog ("was 56 dp intermediate A18, 38 dp… 40 dp in A17, 60 dp pre-A17") | §3.2 presentation, §3.4 numerics | Partly — `chart_axis_helper_test.dart` | REMOVE. The size-history changelog is the clearest example in the set of a document recording iterations nobody will ever need. **PRESERVE AS TEST** the time-based x-positioning rule (entries map linearly by `recordedAtMs`, fall back to chart-mid when all timestamps are equal) — real, non-obvious, and easy to regress |
| 75 | `widget_catalog/feature_primitives.md` → `_RoutineCard`, `HomeLogoButton` | S-006/S-007/S-008 tap-region iteration history; 71×71 gesture bounds; 8 px transparent padding | §3.2, §3.4, §3.7 | Yes — `pr6…_test.dart`, `home_logo_press_affordance_test.dart` | REMOVE |
| 76 | `widget_catalog/layout_and_inputs.md` → `OmniBottomCTA`, `OmniCardHeader`, `OmniBackHeader` | Heights, radii, `kToolbarHeight` (56 px), padding defaults | §3.2, §3.4 | Yes — `header_standardization_test.dart` | REMOVE the values. **PRESERVE** the `OmniCardHeader` enforcement rule ("callers cannot override the style") as a §2.3 invariant — it is already in `global_conventions.md` and should live there alone |
| 77 | `widget_catalog/nutrition_widgets.md` → `LogFoodRow`, `FoodThumbnail`, `_GroupRow` | Selected-state border widths, 16×16 badge, icon names, key naming schemes | §3.2 presentation | Yes — `food_library_*_test.dart`, `nutrition_log_from_library_test.dart` | REMOVE |

## B.7 — `rest_tracking.md`

| # | Section | Claim | Category | Verified? | Rec. |
|---|---|---|---|---|---|
| 78 | `EntryRest` Model + Computed Helper | Full field table and a copied `elapsedSeconds` implementation | §3.5 copied content | Yes — `unified_rest_overlay_test.dart`, `pr4_session_controls_test.dart` | REMOVE the code block; `data_models.md` owns the field table |
| 79 | SQLite Schema | Copied `CREATE TABLE` + `ALTER TABLE` statements (with a stray unbalanced ``` fence) | §3.5 copied content | Yes — `test/db_seed_test.dart` executes the real file | REMOVE; point at `scripts/sqlite_schema.sql` |
| 80 | WorkoutSessionScreen Integration | A code block listing **removed** fields (`Timer? _restTimer;` etc.) under a `// REMOVED:` comment | §3.5 copied content, §3.8 superseded | n/a | REMOVE — documenting what a file no longer contains has no reader |
| 81 | Overlay Display | Copied `_shouldShowRestOverlay()` body and `_formatRestElapsed()` | §3.5 copied content | Yes — `unified_rest_overlay_test.dart` group `Unified rest overlay rule` | REMOVE the code. **PRESERVE** the rule it encodes — "list view and detail view route through one helper so the two surfaces can never disagree" — as a §2.3 invariant |
| 82 | Three visually distinct states table | Background tints and icon names per state | §3.2 presentation | Yes — `pr4_session_controls_test.dart` | REMOVE |
| 83 | "Removed 2026-07-27 (PR 4 refinement)" note | Records that a caption was removed during PR 4 review because it made the chip 2 dp taller | §3.7, §3.2 | n/a | REMOVE — belongs in the plan |

**Worth keeping — this is one of the better documents:** the "Why Wall-Clock
Rest Tracking" section (§2.2 rationale, states the two problems the old design
had); the Record Lifecycle diagram (§2.1); the first-set rule
(`entryIndex == 0` creates no rest record); the paused-rest closing rule
("a paused rest is closed at `restPausedAtMs`, never at `now`") — a §2.3
invariant with real correctness consequences; and the Edit Mode invariant.

## B.8 — Remaining documents

| # | Document / Section | Claim | Category | Verified? | Rec. |
|---|---|---|---|---|---|
| 84 | `app_philosophy.md` → 11. New User Flow | Onboarding inputs → outputs walkthrough | §3.1 flow | Partly | REMOVE |
| 85 | `app_philosophy.md` → 15. MVP Boundary → Deferred | Four deferred items incl. "Wearable integrations" | §3.6 roadmap | n/a | REMOVE — note there are ten 2026-07-13 watch plans in `plans/`, so this list is actively misleading about scope |
| 86 | `app_philosophy.md` → 8. Home Screen Structure | 3×2 tile grid table, "Feb 2026 changes" note | §3.2 presentation, changelog | Partly | REMOVE the layout table; keep the tile *taxonomy* (5 modality tiles + 1 special tile) as §2.4 vocabulary |
| 87 | `calendar_periods.md` → User Workflows 1–5 | Numbered flows: tap-a-day routing rules, day-list behaviour by date, planned-session form mode selector with exact labels | §3.1 flow, §3.3 control inventory | Partly — `calendar_summary_screen_bugs_test.dart` | **PRESERVE AS TEST** the date-sensitive routing rule (past+1 → summary, past+many → day list, today/future → day list) and "past days are read-only" — real, subtle, and I found no direct test. REMOVE the form-control inventory. |
| 88 | `calendar_periods.md` → Monthly Stats Strip | Stat table + layout rules (`Expanded`, `shrinkWrap`, "no scroll") | §3.2 presentation | No | REMOVE |
| 89 | `calendar_periods.md` → Current Limitations | "Recurrence is not implemented"; "smoke test checklist should be run" | §3.6 roadmap | n/a | REMOVE. **PRESERVE** "`recurrenceRule` is a placeholder field, never read" as a §2.3 invariant — an agent could otherwise assume it works |
| 90 | `session_summary.md` → User Workflow + Save as Routine Flow | Arrow walkthrough and 5-step numbered flow | §3.1 flow | Partly | REMOVE |
| 91 | `session_summary.md` → Feeling Survey Capture | Sheet mechanics (`isDismissible: false`), where it does and does not surface | §3.1 flow, §3.2 presentation | Partly — `settings_state_test.dart` covers the toggle | **PRESERVE AS TEST** — "the survey never fires on a calendar-opened historical summary" is a real negative contract that a refactor could silently break |
| 92 | `session_summary.md` → Models | `VolumeComparison` "retained in the model, not rendered" | §3.5-adjacent | Partly | **PRESERVE AS TEST** — dead-but-pinned types need a test, not prose, or they get deleted |
| 93 | `exercise_info_and_notes.md` → User Workflow | Arrow walkthrough with icon names and the 500 ms debounce value | §3.1 flow, §3.2, §3.4 | Yes — `exercise_notes_sheet_test.dart` | REMOVE |
| 94 | `exercise_info_and_notes.md` → Test Coverage | Lists the tests that cover this feature | — | Yes | **KEEP** — this is precisely what §4.2 asks for, and is the best existing example of the pattern in the docs set |
| 95 | `exercise_ranking.md` → Recommended extension points | Three unbuilt ideas (expose score on model, persist scores, multi-tier UI grouping) | §3.6 roadmap | n/a | REMOVE |
| 96 | `exercise_ranking.md` → Example pseudocode | ~20-line invented Dart block | §3.5 copied/illustrative code | No | REMOVE |
| 97 | `rolling_sessions.md` → User Workflow + Free Training Start Sheet | Arrow walkthrough; `SwitchListTile` control inventory; verbatim subtitle copy repeated twice in the same document | §3.1 flow, §3.2 presentation, §3.8 duplication | No | REMOVE the copy and controls. **PRESERVE AS TEST** the `isRolling` immutability invariant ("set at creation, never mutated") and the empty-Free-Training discard rule |
| 98 | `rolling_sessions.md` → `isRolling` table | "Persistence: SQLite column `is_rolling`" | §3.5, **stale** — Hive is the runtime | No | REMOVE |
| 99 | `create_new_exercise.md` → Form Structure §1–5 | Numbered form-section walkthrough with chip labels and field capitalisation | §3.1 flow, §3.2 presentation | Yes — `capitalization_defaults_test.dart` | REMOVE. **PRESERVE** the per-modality capability matrix as §2.3 (it encodes `ModalityConfig.formCapabilities` / `formRequiredCapabilities`) — but drop the literals and point at the constant |
| 100 | `create_new_exercise.md` → Save Flow | Six-step numbered flow | §3.1 flow | Partly | REMOVE. **PRESERVE** the Legacy Capability Handling rules as §2.3 — subtle, and I found no test |
| 101 | `theme_and_settings.md` → Available Themes table | Primary accent hex per theme: `#00B4B8`, `#FF6B35`, `#D4A017`, `#8B5CF6`, `#E53935`, `#1A9A4A` | §3.4 numeric values — **and all six are wrong** | Contradicted. `omni_theme.dart` has `0xFF2DE2E6`, `0xFFFF7B45`, `0xFF24B85A`…; `design_system.md` lists the correct values. Two docs give different hex for the same tokens. | REMOVE — **flagged as high-risk**: an agent picking values from here would hardcode colours that exist nowhere, violating the "theme tokens only" convention while appearing to follow the docs |
| 102 | `theme_and_settings.md` → Settings Screen §1–4 | Section-by-section row inventory with toggle labels | §3.3 control inventory | Yes — `settings_state_test.dart`, `settings_sounds_test.dart` | REMOVE |
| 103 | `theme_and_settings.md` → Version Footer | Format string, source chain, failure fallback | §3.2 presentation | Yes — `startup_failure_screen_test.dart` and the `AppVersionInfo` formatter | REMOVE the format detail. **PRESERVE** the "Hardcoded-string rule" as §2.3 |
| 104 | `profile_and_measurements.md` → UI Behavior → Identity Section | ~10 lines of layout: 200×200 avatar, `headlineMedium`/`w700`, 2 dp inter-row gap, 12 dp horizontal padding, "no `ConstrainedBox(minHeight:)`", why an icon was removed | §3.2 presentation, §3.4 numerics | Yes — `profile_screen_test.dart`, `avatar_crop_test.dart` | REMOVE |
| 105 | `profile_and_measurements.md` → Avatar Crop Step | Widget composition, `pixelRatio: 3.0`, `minScale`/`maxScale`, hint copy | §3.2, §3.4, §3.5 | Yes — `avatar_crop_sheet_test.dart` | REMOVE the specifics. **PRESERVE** the rationale ("the avatar displays as a circle, so an off-centre subject clips badly") and the `OmniNavigator.push` requirement (§2.3) |
| 106 | `profile_and_measurements.md` → Lean Mass computed row | Formula, em-dash fallback, "no `maxLines: 1` constraint" | §3.2 presentation | Yes — `profile_validation_test.dart` | REMOVE the presentation. **PRESERVE AS TEST** the invariant "pre-existing `lean_mass` entries are preserved but not used as the display source" — silent data behaviour with no obvious test |
| 107 | `db_integration.md` → Setup And Validation | Numbered `flutter test` command walkthrough | §3.1 flow | n/a | REMOVE — belongs in a README or the pipeline command files |
| 108 | `db_integration.md` → SyncService Integration Surface (forward-looking) | Speculative code for a service that does not exist | §3.6 roadmap | n/a | REMOVE |
| 109 | `db_integration.md` → Data-migration version sequence | 14-row legacy-marker → version mapping table | §3.4 numeric values defined in `data_version.dart` | Yes — `test/data_migration_test.dart` | REMOVE the table; keep the mechanism description (§2.1) and the idempotency invariant (§2.3) |
| 110 | `data_models.md` (whole document, ~875 lines) | Field-by-field tables mirroring every class in `lib/data/models/models.dart` | §3.5 copied implementation content | Partly — `test/models_test.dart` | **Decision needed, not a simple remove.** Under §3.5 this document should not exist; the source is the model file. But it is the most-referenced doc in the set and its *relationship* content (which model owns which FK, snapshot-freezing semantics) is legitimate §2.1/§2.3. **Recommendation: keep as an exception scoped to relationships and invariants; drop the field tables.** |
| 111 | `state_management/workout_state.md` → SyncService Integration Surface | Same speculative sync code, twice in one document | §3.6 roadmap | n/a | REMOVE both |
| 112 | `state_management/workout_state.md` → `previousValues` defaults | `reps=10`, `weight=0.0`, `extra-weight=0.0` | §3.4 numeric values | Yes — `exercise_set_last_value_test.dart` | REMOVE the literals; keep the carry-forward contract |
| 113 | `state_management/*.md` (all four part pages) | Method tables mirroring public APIs | §3.5-adjacent | Partly | **No action recommended.** These are the most conformant substantial docs in the set — method tables sit close to §2.1 structure. Flagged only so the boundary is explicit: a method *name and responsibility* is structure; a signature restated with defaults is copied content. |
| 114 | `navigation_contract.md` → Visual tradeoff (accepted) | "~300 ms slide", "5%-opacity radial highlight" | §3.2, §3.4 | No | REMOVE the numbers only. The section is otherwise a model §2.2 rationale entry. |
| 115 | `global_conventions.md` → link targets | Rules reference `docs/theme_and_settings.md`, `docs/stats_screen.md` etc. — several of which this audit recommends gutting | — | n/a | **No violation.** Flagged as a dependency: if you accept removals, these pointers need rechecking. |

---

# PART C — Documents found fully conformant

Assessed against the standard and found to require **no changes**:

1. **`state_management.md`** — index, page routing table, class → page lookup,
   dependency graph. Pure §2.1 structure. No behaviour, no presentation, no
   roadmap. Exemplary.
2. **`widget_catalog.md`** — index, widget → page lookup, directory structure,
   and a "Not yet catalogued" table that makes gaps visible rather than
   silent. Pure §2.1. The "What Changed in the Split" section is a one-time
   migration note that could go, but it is factual and bounded.
3. **`global_conventions.md`** — six cross-cutting rules, each naming where to
   look. Pure §2.3 invariants. Already the shape the whole set should take.
   *(Minor: it lacks an explicit §4.1 scope line, though its opening sentence
   is close enough that this is not worth an entry.)*

Conformant **by exemption** under standard §6, not by assessment:

4. **`docs-audit-2026-07-26.md`** — a dated audit record, exempt as a frozen
   artefact. Recommend it move to `history/` for consistency with §6.
5. **`history/route-migration-audit.md`** — already carries HISTORY framing and
   is correctly located.

Every other document in the folder has at least one entry above.

---

# PART D — Notes for the reviewer

## D.1 A contradiction in the task specification

The task asks for two artefacts and states in **Out of scope**: *"Do not write,
modify, or delete any tests"*, with the acceptance criterion *"`git diff` shows
only two added files."* The **Unit Tests Required** section separately asks for
*"a test asserting the standard document exists at its expected path."*

These cannot both hold. I followed the out-of-scope instruction and the
two-file criterion, and wrote **no test**. The second test requirement
(covering a re-runnable audit script) did not apply — this audit was produced
by hand, not generated.

If you want the existence test, here is the change to make as a follow-up. It
is a three-line addition to the existing `test/docs_indexing_contract_test.dart`,
which already walks this folder:

```dart
test('documentation standard exists at its canonical path', () {
  expect(
    File('$_docsRoot/documentation_standard.md').existsSync(),
    isTrue,
    reason: 'The documentation standard must not be silently deleted.',
  );
});
```

## D.2 Existing tests that read documentation

The task flags tests that read or assert on documentation content as "the
antipattern this work exists to remove". One test does this:

**`test/docs_indexing_contract_test.dart`** — walks `.github/agents/docs/`,
asserts no file exceeds 64 KiB, and checks that internal links resolve.

**My recommendation is to keep it, and I want to be explicit about why I am
not treating it as the antipattern.** It asserts *structural* properties —
file size and link resolution — not behavioural claims. It cannot go stale
when the app changes, because it does not describe the app. The antipattern is
a test that pins prose describing behaviour; this pins retrievability. It is
also the mechanism that caught the 95 KB widget catalog whose tail was
unreachable.

Note that the existence test in D.1 would be the same kind of test, which is a
second reason to think this category is legitimate.

No other test asserts on documentation content. `navigation_contract_enforcement_test.dart`,
`hub_interaction_test.dart`, and `pr2_launch_quality_hotfix_test.dart` matched a
docs-path grep only because they mention paths in comments.

## D.3 Pre-existing working-tree state

`lib/features/home/home_screen.dart` was already staged as modified when this
task began, and ten untracked plan files were already present under
`.github/agents/plans/`. **Neither was touched by this work.** `git status`
will therefore show more than two entries; `git status --porcelain` filtered to
this task's changes shows exactly two additions:

- `.github/agents/docs/documentation_standard.md` (new)
- `.github/agents/plans/docs-standard-audit-2026-07-30.md` (this file)

## D.6 Test status — one pre-existing failure, one introduced by this task

`flutter test test/docs_indexing_contract_test.dart` currently reports **two**
failures. They have different causes and different owners.

**1. Broken relative links — PRE-EXISTING, not caused by this task.**
Both `README.md` and `feedback-pack-baseline-2026-07-27.md` link to
`../plans/2026-07-27-00-feedback-pack-shipping-order.md`, which does not exist.
Verified by re-running the suite with the new standard removed: the failure
reproduces identically. Recorded as audit item 116.

**2. The new standard is unreachable — INTRODUCED by this task, and I could not
fix it within the task's constraints.**

The test's `every doc page is reachable from another doc page` check fails on
`documentation_standard.md`, because no document links to it. That check passes
without the new file (`+4 -1` instead of `+3 -2`).

Fixing it requires an inbound link, which requires editing a file inside
`.github/agents/docs/` — specifically `README.md`. That directly violates two
stated acceptance criteria: *"No file under `.github/agents/docs/` has been
modified apart from the addition of the new standard"* and *"`git diff` shows
only two added files."* There is no way to satisfy both the reachability test
and the two-file constraint, so I left the constraint intact and am flagging
the failure rather than silently choosing.

**The one-line fix, for whenever you lift the constraint** — add to the
"Shared Conventions" table in `README.md`:

```markdown
| [Documentation Standard](documentation_standard.md) | What these documents may and may not contain; required scope block; verification-pointer rule |
```

That single row resolves failure 2. Failure 1 needs the dead shipping-order
links removed or repointed (item 116).

## D.4 Patterns worth noting before you decide

**The inverted-annotation failure is systemic, not incidental.** Every
"Scheduled, not current" note in the set has inverted. The pattern of writing
future behaviour into a reference doc has a 100% failure rate here, which is
why standard §3.7 prohibits it outright rather than asking for discipline.

**Self-contradiction is the most reliable staleness signal.** Six documents
contradict themselves or each other: `modality_based_exercise_ui.md` on
Stopwatch usage; `stats_screen.md` on section count; `my_routines.md` on the
overflow menu and on segment grouping; `modality_tracking.md` vs
`exercise_ranking.md` on picker partitioning; `design_system.md` vs
`theme_and_settings.md` on theme hex values; `app_philosophy.md` vs
`navigation_and_screens.md` on maintenance-sheet item count. Where two docs
disagree, at least one is wrong and neither reader can tell which.

**Correction notes decay too.** Several 2026-07-26 audit corrections have
themselves gone stale (item 25 is a correction that was already wrong again
four days later). Correcting prose in place does not fix the class of problem —
which is the argument for this standard rather than another audit pass.

**Volume is the risk multiplier.** The three least conformant documents
(`modality_based_exercise_ui.md`, `my_routines.md`, `stats_screen.md`) are also
among the four largest. Conforming to the standard would remove an estimated
55–65% of the folder's total line count, with essentially all of the loss in
content that a test either already covers or should.

## D.5 Suggested review order

1. **Part A first.** These are false statements with a live blast radius. Items
   1, 9, 11, 16, and 20 are the ones most likely to have already produced
   incorrect agent work.
2. **Then the ~20 `PRESERVE AS TEST` items** — the real institutional-knowledge
   decisions. Items 32, 35, 46, 48, 69, 74, 87, 91, 97, 100, and 106 are the
   ones I would most regret losing.
3. **Then the two scoped-exception decisions**: `design_system.md` (B.3) and
   `data_models.md` (item 110). Both are "should this document exist under this
   standard at all", and neither should be settled by an agent.
4. **Everything else** is mechanical once the above are decided.
