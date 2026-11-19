# S5 — UI rules decided in plans, part 2 (40 plans)

Scout sheet. Read-only survey of `docs/plans/` part-2 plans: goal / requirements / decisions only
(no `.evidence.md`, no `.review.md` opened). Evidence quotes are verbatim from files viewed this run.

---

## STALE-DOC

### remove-app-launch-resume-modal — widget catalog still documents a resume dialog that no longer exists
- File: `docs/widget_catalog.md` · Symbol: "Note on resume dialog" · ~line 22
- Current lines (verbatim):
  ```
  Note on resume dialog:
  - The cold-start `Unfinished Session` dialog is implemented as a private, screen-local widget in `HomeScreen` (`_ResumeSessionDialog`).
  - It is intentionally not promoted into `lib/widgets/` because it is feature-specific and not reused across screens.
  ```
- Code now: grep `lib/` for `_ResumeSessionDialog|ResumeSessionDialog` → No matches found. `lib/features/home/home_screen.dart` does a silent restore instead:
  ```
  // Silent session restoration logic
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!mounted || widget.workoutState.hasActiveSession) return;
    final session = await widget.workoutState.checkForInProgressSession();
    if (session != null && mounted) {
      await widget.workoutState.loadHistoricalSession(session.id);
    }
  });
  ```
  (`lib/features/home/home_screen.dart:170-175`; `initState` also calls `checkForInProgressSession()` at :139.)
- Also stale: `docs/releases/2026-05-plan-review.md:25-26` — "If an in-progress session exists in storage, home presents an `Unfinished Session` dialog with continue/discard actions."
- Related: `unfinished-session-modal-set-count` plan Feedback records "Does Not Meet Plan" (resume flow missing); `docs/plans/routine-add-sets-bug-plan.md:127` says "Re-introduce the cold-start resume flow in HomeScreen per that plan's Feedback before merging". The flow was instead replaced by the silent restore above.

### remove-general-modality — ModalityPickerDialog catalog entry says "five modalities plus a General option"; code has four, no General
- File: `docs/widget_catalog/session_widgets.md` · Symbol: `ModalityPickerDialog` · lines 239-242
- Current lines (verbatim):
  ```
  - Shows all five modalities plus a "General" option
  - Returns `(true, String? modality)` record when the user picks an option:
    - Specific modality: `(true, 'cardio_endurance')` etc.
    - "General": `(true, null)`
  ```
- Code now: `lib/widgets/pickers/modality_picker_dialog.dart:64-70`
  ```
  final modalities = [
    ('cardio_endurance', 'Cardio', Icons.favorite),
    ('resistance_lifting', 'Resistance', Icons.fitness_center),
    ('sports', 'Sports', Icons.sports_basketball),
    ('isometric_stretching', 'Isometric', Icons.accessibility),
  ];
  ```
  No "General" anywhere in the file (grep `General` in that file → only this options list context, no general entry).
- Note: `MetricChooserDialog` still exists at `lib/widgets/pickers/metric_chooser_dialog.dart` (seen in grep output).

---

## NO-RULE

### screen-transition-animation — Cupertino-slide-on-all-platforms transition rule is not in the navigation docs
- File: `lib/core/navigation/omni_route.dart` · Symbol: `OmniRoute` · lines 10-11, 59
- Current lines (verbatim):
  ```
  /// Uses [CupertinoPageTransitionsBuilder] on all platforms (slide + edge-swipe-back
  /// on iOS/macOS) for a consistent, smooth transition everywhere.
  ```
  ```
      const builder = CupertinoPageTransitionsBuilder();
  ```
  (`transitionDuration` is 300 ms at :41.)
- Docs: `docs/navigation_and_screens.md:5-7` documents only the route-type rule:
  ```
  > **Rule**: All screen-level navigation goes through `OmniNavigator`. `OmniRoute` and `OmniFadeRoute` are the only route types used for screen pushes. Any `MaterialPageRoute` or `PageRouteBuilder` outside `lib/core/navigation/` is a **code-review blocker**.
  ```
  No statement of the transition style (Cupertino slide everywhere, 300 ms). Grep `docs/navigation_and_screens.md` for `Cupertino|transition` → only bleed-through/opacity prose.
- Guard: `test/omni_route_test.dart` exists (glob).

### nutrition-foods-i-eat-empty-state — empty-state message and no-CTA rule not documented
- File: `docs/widget_catalog/home_screen.md` · Symbol: Foods I Eat section · ~line 136
- Current line (verbatim):
  ```
  branches into loading, empty, and data states
  ```
  (context: the section describes the Foods I Eat card's states; no message wording, no "list stays put, no empty-state CTA" rule)
- Guard exists: `test/nutrition_test.dart:881-884` (and :940, :997, :1075, :1125) assert `find.textContaining('Foods I Eat list is empty')`.
- The plan's rule (exact message + no CTA in the empty state) lives only in the plan.

### session-detail-spacing — live-mode LOGGED label / center Start-control rule not in docs
- Searched: grep `LOGGED` in `docs/` → matches only in `docs/plans/**` (plan files), none in the standards docs.
- `docs/widget_catalog/session_widgets.md:55` documents the adjacent rule:
  ```
  Play/pause control is a separate Start button — not a tap on the value display. Timed and drill timers render at the dominant tier; the play/pause status label sits on a line below the value.
  ```
- The plan's LOGGED-label / hidden-Log-Set-while-running rules are undocumented. Note: the later edit-historical-session plan removed the LOGGED label from edit mode, so only the live-mode rule is at stake.

### timed-emphasis-redesign + typography-control-styling — neutral weight-adjustment chip styling not in docs
- File: `docs/widget_catalog/session_widgets.md` · ~line 55 (timer tier documented; chip not)
- Current line (verbatim):
  ```
  Play/pause control is a separate Start button — not a tap on the value display. Timed and drill timers render at the dominant tier; the play/pause status label sits on a line below the value.
  ```
- Grep `docs/widget_catalog/` for `Weight adjustment` → only `session_widgets.md:124` (value-adjustment math, no styling rule). The OutlinedButton/neutral-chip rule from `typography-control-styling` (fixes 1-3, tests A/B/C in `test/screen_widget_test.dart` per plan Progress [x]) is plan-only.
- Emphasis-tier interplay IS documented (`session_widgets.md:53`: "When `isReadOnly` and `emphasisTier` are both set, the emphasis tier wins and the value is not dimmed"); `test/timed_emphasis_redesign_test.dart` exists (glob). Later `exercise-detail-emphasis-tier-rebalance` superseded the secondary tier with dominant (D-4 button-label color in its plan, not docs).

### weight-increment-defaults — 0.5 increment rule not in docs; no test found
- Searched: grep `docs/` for `0.5` increment rule → only plan files (`crown-control-tap-to-edit`, `tap-to-edit-metric-modal` test-name references). No standards doc states the 0.5 default increment for weight entry.
- Searched: grep `test/` for `increments by 0\.5|0\.5 step|step.*0\.5` → No matches found. The plan's named regression tests were not found by these patterns (partly checked — differently worded assertions may exist).

---

## NO-GUARD

### theme-system-overhaul — dialog barrier-opacity rule dropped from code and unguarded
- Plan rule: picker/dialog barrier opacity ≥ 0.7 (`Colors.black.withOpacity(0.78)`) at every `showDialog` launch point, with a widget regression test.
- Searched: grep `lib/` for `0\.78|withOpacity\(0\.7` → No matches found. Grep `lib/` for `barrierColor` → only `lib/core/navigation/omni_route.dart:44` `Color? get barrierColor => null;` (route, not dialog).
- Searched: grep `test/` for `0\.78|barrier.*opacity` → nothing relevant.
- The rule is neither in code nor guarded; the later `confirmation-dialog-consolidation` plan standardized the two-tier `ConfirmationDialog` (documented in `docs/design_system.md:358-364` with barrierDismissible true and 22 call sites) but does not restate a barrier-opacity floor.

---

## Unfinished plans (rules not yet in force — no finding)

### typography-text-scale-audit — Phases 4-5 pending
- `docs/plans/typography-text-scale-audit-plan.md:536-538` (verbatim):
  ```
  - [ ] Phase 4: New typography scale tests + existing test review
  - [ ] Phase 5: Design system doc update, widget catalog update, typography_contract.md, audit report shell
  ```
  (Phase 3.22 marked "**Phase 3 Complete**" at :535.)
- Not on disk: `test/typography_scale_test.dart` (glob → no files), `docs/typography_contract.md` (glob `docs/typography*.md` → no files). `docs/design_system.md:141-155` still carries the sparse 4-row table + 4 rules; the plan's 6-rule set (no fontSize literals, overflow strategy, FittedBox on 56dp buttons, Row width budget, chart-axis exception comment, single-location clamp) is not there.

### train-screen-non-scrolling-layout — Phase 2 pending; code and tests still on the old contract
- `docs/plans/train-screen-non-scrolling-layout-plan.md:264-270` (verbatim):
  ```
  - [x] Phase 0 — Plan (this file)
  - [ ] Phase 1 — Data Layer (N/A — no model / repo / schema changes)
  - [ ] Phase 2 — Logic & UI
    - [ ] Add `NutritionSummaryCard.minHeight` constant
    - [ ] Restructure `home_screen.dart` grid + summary layout
  ```
- Code: `lib/features/home/home_screen.dart:1015` `child: CustomScrollView(`; :1257 `gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(`.
- Test: `test/screen_widget_test.dart:2021` `expect(find.byType(CustomScrollView), findsWidgets);` (group "renders energy tile grid") — the opposite of the plan's rule. `test/home_train_layout_test.dart` does not exist (glob).

### timer-start-on-exercise-select — no step executed
- `docs/plans/timer-start-on-exercise-select-plan.md:66-76` (verbatim):
  ```
  ## Progress
  - [ ] Add resetSessionTimerStart() to session_core_lifecycle.dart
  - [ ] Expose proxy on workout_state.dart
  - [ ] Guard _tick() when no exercises yet
  - [ ] Reset timer on first exercise add in _addExercise()
  - [ ] Manual smoke-test
  - [ ] Run tests
  ```
- The rule "The session clock stays at `00:00` until the first exercise is added" appears in `docs/releases/2026-05-plan-review.md:23` — a release-review doc, not a standards doc; no doc/test guard verified.

---

## Superseded / removed features (rules obsolete — no finding)

- **stats-feeling-chart-width-consistency, stats-feeling-color-dry-fix, stats-feeling-trend-color-visibility** — the feeling trend chart no longer exists: grep `lib/features/stats` for `Feeling|feeling` → No matches; grep `docs/stats_screen.md` for `feeling` → No matches. Removed by later stats plans. (`feelingColor` itself still lives in `lib/core/utils/session_feeling_utils.dart` and is documented in `docs/design_system.md`.)
- **stats-rest-time-chart** — the REST TIME chart is gone: grep `lib/features/stats` for `RestTime|rest_time|restTime|REST TIME` → No matches; no REST TIME section in `docs/stats_screen.md`.
- **session-summary-top-stats-card** — the 4-metric top card was superseded: `docs/session_summary.md:10` "Session info card (Duration and Rest Time for standard sessions; the EFFORT row for every session)" and :50 same; `test/screen_widget_test.dart:5127` "top stats show only Duration and Rest Time".
- **routine-rest-menu-and-session-detail-icons** — the 44×44 icon rule was superseded by a 40 dp compact floor: `test/exercise_notes_sheet_test.dart:156` "Exercise detail header icons share compact size, 40pt hit targets, and remain tappable", :199-201 `expect(infoButton.constraints!.minWidth, 40.0);` / `minHeight, 40.0`. (44 dp guards exist elsewhere: `test/exercise_row_density_test.dart:292,297`, `test/pr6_routine_session_entry_navigation_test.dart:1025`.)

---

## Checked, nothing to report

timed-emphasis-redesign (tier + isReadOnly interplay documented, `session_widgets.md:53,55`; test exists), unified-rest-overlay-rule (`docs/rest_tracking.md:182` `_shouldShowRestOverlay()`; `test/unified_rest_overlay_test.dart` exists), value-entry-select-on-focus (catalog entries + `test/value_entry_select_on_focus_test.dart`), tap-to-edit-unification (`test/tap_to_edit_unification_test.dart`; crown-dormant + tap-to-edit documented), tap-to-edit-metric-modal (catalog + plan test names), timer-alerts-sound-system (`docs/theme_and_settings.md:85`, `docs/state_management/app_state.md:140-153`, `docs/design_system.md:182`), 2026-10-04-10b-stats-pr10b-primer-sheet-plan (`docs/stats_screen.md:11-56` with test names), 2026-10-12-24-stats-clarity-plan (Progress P1-P4 [x]; `docs/stats_screen.md:103-108,153-161,185,367-371`), unified-card-and-header (`docs/design_system.md:160` D-1 + header table + overflow rules), profile-identity-horizontal-header (`docs/profile_and_measurements.md:85-87`), routine-builder-no-duration-target (`docs/my_routines.md:271,276`), unsaved-changes-popup (`docs/modality_based_exercise_ui.md:347-351` "Unsaved Changes Dialog … Verified by `test/unsaved_changes_dialog_test.dart`"; `docs/my_routines.md:40`; discard styling `docs/design_system.md:358`), stats-nutrition-trend-card (`docs/nutrition.md:244-245` total-carbs callout), testflight-ui-fixes (set-dot fill documented `docs/modality_based_exercise_ui.md:75,295`; guarded `test/resistance_emphasis_redesign_test.dart:310,354,493`; theme-token/56dp/16dp items covered by global_conventions rule 2 and design_system tokens), modality-color-consolidation (`docs/design_system.md` rule 7; `docs/session_summary.md:85-87`), session-scroll-bottom-padding (pure numeric spacing, per standard not doc material), routine-focus-modality-inheritance (picker-scope documented in catalog "Where it does NOT appear"), routine-modality-picker (same catalog entry), routine-exercise-detail-ui-parity (documented per earlier read), stats-scrollable-trend-charts (`docs/profile_and_measurements.md:135-139`; catalogued), unify-chart-scrolling-popup (D-1..D-12 invariants; no-popup rule behavioral, scroll documented), theme-support (six-theme roster + palette gates in `docs/design_system.md`; settings Appearance in `docs/theme_and_settings.md` — selector detail not re-verified), theme-system-overhaul machinery (six themes + gates documented; barrier-opacity item reported above), remove-general-modality (picker scope documented; stale "General" text reported above), remove-app-launch-resume-modal (silent restore is the live behavior; stale doc reported above), unfinished-session-modal-set-count (state logic done; resume-flow gap reported under STALE-DOC), nutrition-foods-i-eat-empty-state (test-guarded; wording gap reported above), session-detail-spacing (gap reported above), weight-increment-defaults (gap reported above), timed-emphasis weight chip (gap reported above).

---

## Extras (UI-suggesting plans in `docs/plans/` not in brief-s4 or brief-s5)

Named from glob of `docs/plans` (keyword families: cta, dialog, sheet, empty, toast, label, spacing, icon, chart, plus screen/UI names seen in the same glob):

- shared-bottom-cta-plan.md
- routines-bottom-cta-plan.md
- add-food-screen-bottom-cta-plan.md
- day-session-list-bottom-cta-plan.md
- primary-bottom-cta-anchor-width-plan.md
- exercise-picker-page-plan.md
- exercise-picker-auto-open-plan.md
- exercise-info-notes-plan.md
- exercise-row-density-fix-plan.md
- session-set-management-relocation-plan.md
- session-toolbar-rework-plan.md
- session-summary-open-calendar-plan.md
- rest-timer-docked-strip-plan.md
- foods-i-eat-thumbnail-toggle-plan.md
- food-log-thumbnail-contrast-plan.md (in brief-s4 — excluded)
- food-library-edit-image-plan.md
- nutrition-food-library-add-plan.md
- food-last-amount-plan.md
- avatar-crop-step-plan.md
- calendar-month-grid-height-cap-plan.md
- measurement-history-chart-readability-plan.md (in brief-s4 — excluded)
- daily-nutrition-macro-chart-plan.md (in brief-s4 — excluded)
- hub-bottom-sheet-single-step-open-plan.md (in brief-s4 — excluded)
- onboarding-plan.md
- preflight-ux-improvements-plan.md
- first-unlogged-set-landing-plan.md
- finish-session-stops-timers-plan.md
- edit-session-duration-plan.md
- disable-feeling-survey-setting-plan.md
- gradient-window-layer-plan.md
- home-nutrition-strip-plan.md
- boxing-rest-timer-reset-bug-plan.md
- height-unit-preference-plan.md
- timed-extra-weight-plan.md
- resistance-framework-extra-weight-visibility-plan.md

(Items marked "in brief-s4 — excluded" appeared in the same glob but are already covered; listed for transparency.)
