# Feature: Session Effort Rating Redefines "How Did It Feel" (Phone)

> Status: CLOSED. Phases 1–5 are implemented and code-reviewed (CHANGES REQUESTED → addressed). It is on `develop` as dcfe474 (implementation) and ae71e23 (review fixes), and not yet pushed to origin as of 2026-09-27.
> Next handoff: none. The next Stats work is the PR 3 series: `.github/agents/plans/2026-09-26-03-stats-pr3-distance-series-index.md`.
> Binding conventions: docs/global_conventions.md + docs/session_summary.md, docs/calendar_periods.md, docs/stats_screen.md, docs/theme_and_settings.md, docs/design_system.md

## Overview

Redefine the post-workout "feeling" survey as an effort-rating survey. Keep the survey's mechanics (same moment, same five tiles, same must-answer sheet, same settings toggle), but change what it asks, how it's labeled, and how it colors. Add the ability to add or change the rating from the Session Summary (both fresh and past sessions). Replace the calendar's feeling-based border tint with an effort-intensity ramp, and remove the HOW DID IT FEEL section from Stats. Historic feeling answers are read as effort ratings on the same scale without conversion.

**Scope**: Phone only. watchOS, distance, Instruments, Mix, and Signals are separate items. This PR captures the foundation: the prompt redefinition, the add/change control, color scheme, settings relabel, and doc updates. Every change aligns with decisions D-4 through D-7 and D-13, D-14 from the Stats Redesign Prompt Pack (settled 2026-09-24).

**Success criteria**: The feeling survey becomes the effort-rating survey, users can add or change ratings after a session, the calendar shows effort intensity at a glance, and Stats reflects the new purpose.

---

## Resolved Decisions (Ledger)

### From Stats Redesign Pack (Binding)

| ID | Decision |
|---|---|
| **D-4** | **The effort rating redefines the feeling prompt, same sheet same moment.** Same five numbered tiles, same non-dismissible sheet, same must-answer rule, same stored `TrainingSession.sessionFeeling` field, same settings toggle (relabelled). Title: "How hard was this session?". End labels: "Very easy" (1) and "Max effort" (5), replacing "Rough" and "Great". No per-number words. |
| **D-5** | **Past feeling answers are effort ratings, no conversion.** An answer stored before the redefinition is read as a rating on the same scale. A past "Great" (5) now reads as "Max effort"; a past "Rough" (1) as "Very easy". |
| **D-6** | **The rating can be added or changed from the Session Summary.** Works on post-workout Summary and on a past session's Summary opened from the calendar. |
| **D-7** | **Colors: one-color intensity ramp.** Theme accent, faintest at 1, full strength at 5, on tiles and calendar border. "More", never good/bad. Every step must pass `test/palette_legibility_contract_test.dart` on every theme. Never relax a contrast assertion to fit a value. |
| **D-13** | **Documentation follow-through.** Update Session Summary, Calendar, Settings, and Stats docs. Remove false claim that the survey sheet has a close/skip control. |
| **D-14** | **Storage: reuse the existing field.** Keep using `TrainingSession.sessionFeeling`; no migration. The never-written `perceivedSessionRpe` (1–10) field stays unused. |

### Technical Decisions (This Plan)

| ID | Decision |
|---|---|
| **T-1** | **Intensity ramp derivation: deterministic rule.** Each step is the theme accent (`primary`) alpha-composited over `surface`. Step 5 = `primary` (100% opacity; already passes ≥3:1 vs `surface` by contract check 8). Step 1 = lowest alpha where the composite reaches ≥1.8:1 vs `surface` (same floor as contract check 6 for `surfaceBorder`). Steps 2–4 = contrast spaced evenly: each step's contrast-vs-surface sits evenly between step 1's and step 5's (its alpha is the one whose composite lands closest to that target), so contrast strictly increases monotonically. Add to `test/palette_legibility_contract_test.dart` three contract checks for every ramp step on every theme: (a) step n ≥ 1.8:1 vs surface, (b) contrast strictly increases step 1→5, (c) the number text (headlineSmall) on each filled tile reaches ≥3:1 in contrast, using whichever of `onPrimary` or the dominant text color passes (the helper is the same one the UI will use). Never relax a threshold. If a theme cannot satisfy (a)–(c), stop and report Blocked; do not tune quietly. |
| **T-2** | **Summary effort row: always-on, in-stats-area placement.** The Session Summary's stats section always displays an "EFFORT" row (even if toggle is off): label "EFFORT", value drawn as "n / 5" when rated, or "—" when unrated. Per D-15 the value text uses the stat pills' shared value color (the `_StatPill` default), and the rating's intensity is a non-text mark: a 12×12 rounded square (corner radius 3) filled with that step's ramp color (`feelingColor(n, themeColors)`), immediately before the value text with an 8dp gap; unrated sessions have no square. Place this row inside the existing summary stats area using the existing `_StatPill` / stats-grid pattern; The EFFORT row goes in the first Summary card (`_buildSessionInfoCard`, key `omni_session_info_card`), as a second full-width row beneath the existing Duration | Rest Time row, separated by the same 16dp gap: `_StatPill(label: 'Effort', …)` on the left (the pill upper-cases it to "EFFORT") and the trailing text button on the right. (Pinned by the orchestrator on review, 2026-09-24.) The row's trailing text button reads "Change" when rated, "Add rating" when unrated. Tapping it opens the SAME sheet widget as the post-workout prompt (title "How hard was this session?", end labels "Very easy"/"Max effort", 1–5 tiles), pre-selecting the current value. DIFFERENCE from the automatic prompt: this user-opened sheet CAN be dismissed without a choice (tap outside or swipe down); dismissing changes nothing. Only the automatic post-workout prompt is must-answer. Picking a value saves through `WorkoutState.updateSessionFeeling`, closes the sheet, and the effort row updates immediately. Works on both post-workout Summary and calendar-opened (historical) Summary. |
| **T-3** | **Theme color updates.** All intensity-ramp color definitions live in `lib/core/constants/omni_theme.dart`, derived per T-1. Every color is tested against `test/palette_legibility_contract_test.dart` before merge; the test must pass without exception and must not be disabled for any step. |
| **T-4** | **Settings toggle label: exact text, no migration.** The toggle label in Settings is exactly "Effort Rating" with subtitle exactly "Ask how hard the workout was after finishing". The preference key stays `show_feeling_survey` and the stored boolean value is unchanged. Every user's existing on/off choice is preserved without any code intervention. |

### Review Follow-up Decisions (orchestrator defaults, owner to confirm)

| ID | Decision |
|---|---|
| **D-15** | **(orchestrator default, owner to confirm) EFFORT value legibility.** Drawing "n / 5" in the ramp color fails the design system's text-contrast rule (step 1 is about 1.8:1 against the card on every theme; checks 18a–c cover the ramp as a fill, not as text). The EFFORT value text is therefore drawn in the same color as the other stat pills (the `_StatPill` default), and the intensity is carried by a non-text mark: a 12×12 rounded square (corner radius 3) filled with `feelingColor(n, themeColors)`, placed immediately before the value text with an 8dp gap. Unrated sessions show "—" and no square. Owner may veto. |
| **D-16** | **(orchestrator default, owner to confirm) Rating-sheet subtitle date.** The sheet subtitle was hard-coded "<modality> · Today", so a past session opened from the calendar read "· Today". The sheet now receives the session's start time: it shows "· Today" when the session started today (local date) and otherwise the date in the Summary's existing short-date style (e.g. "Sep 18"), reusing the Summary's `_formatDate`. Owner may veto. |

---

## Feature Invariants

Only invariants that bite in this feature:

- **Effort rating field is session-scoped.** `TrainingSession.sessionFeeling` is the sole canonical storage; it is never duplicated or shadowed elsewhere. D-14 ensures this. Past survey answers are read with no rewriting.
- **Colors are theme-aware.** The intensity ramp and every color boundary (tiles, calendar tint, Stats removal verification) must use the active theme's tokens and pass the legibility contract on every theme (D-7). No hardcoded colors.
- **Settings toggle preserves user state without migration.** A user with the toggle on stays on, off stays off, across the label change. No code-side logic needed; the preference key is unchanged (T-4).
- **Effort rating appears nowhere in UI text except the redefined prompt.** "How did it feel", "Rough", and "Great" are removed entirely. The calendar, Summary, and Stats refer to it only by its new purpose (effort, rating, intensity).
- **Sheet mechanics unchanged.** Post-workout prompt is non-dismissible, must-answer, appears once per session. Historical summary (calendar-opened) never shows the prompt. A session already answering the prompt on the calendar offers the add/change control, not the prompt again.
- **Repository parity holds.** `HiveWorkoutRepository` and `MockWorkoutRepository` both implement the same `updateSessionFeeling(sessionId, value)` call with identical persistence. Mock must mirror Hive value-for-value on all session reads. No model changes expected; this field already exists.

---

## Requirements

From the Copilot Prompt and Acceptance Criteria in the Stats Redesign Pack:

1. The post-workout survey asks "How hard was this session?", 1–5 scale.
2. End labels read "Very easy" and "Max effort" (not "Rough" and "Great").
3. No per-number labels below the tiles.
4. Same must-answer, non-dismissible, once-per-session behavior.
5. Selection closes the sheet and persists the rating.
6. A session without a rating offers a way to add one from the Summary.
7. A session with a rating shows the value on the Summary and can be changed there.
8. Works for both fresh sessions (post-workout Summary) and past sessions (calendar-opened Summary).
9. Calendar day-session-list border shows the rating on an intensity ramp (no tint for unrated).
10. Settings toggle relabeled and preserved.
11. Every color step passes the legibility contract on every theme.
12. HOW DID IT FEEL section removed from Stats screen.
13. Past answers are read as effort ratings, unchanged.
14. Docs updated; false close/skip claim removed.

---

## Acceptance Criteria

All criteria from the Stats Redesign Pack item 1, restated here for implementation:

- [ ] Post-workout prompt shows "How hard was this session?" with "Very easy" at 1 and "Max effort" at 5. No "Rough", "Great", or "How did it feel" appears anywhere in the app.
- [ ] One tap stores the answer and closes the sheet.
- [ ] Sheet cannot be dismissed without a choice.
- [ ] Prompt doesn't reappear for a session that already has a rating.
- [ ] A session with no rating offers a button/control on its Summary to add one.
- [ ] Changing the rating from the Summary replaces the stored value; reopening the Summary shows the new value.
- [ ] Works for both fresh (post-workout) Summary and past (calendar-opened) Summary.
- [ ] With the toggle off, no post-workout prompt appears. User's prior on/off choice is preserved.
- [ ] Calendar day-session-list shows unrated sessions with no tint, rated sessions with gradient-step tints (1 faintest, 5 strongest, all same color).
- [ ] Every tint step passes `test/palette_legibility_contract_test.dart` on every theme.
- [ ] A session answered before the redefinition shows the rating as-is (e.g., past "Great" reads as 5 = "Max effort").
- [ ] Stats screen no longer has a HOW DID IT FEEL section.
- [ ] Docs (Session Summary, Calendar, Settings, Stats) describe the effort rating and remove the false close/skip claim.

---

## Scenarios

All fixtures are concrete; every scenario is enumerated.

### S-1: Fresh Session, Toggle On, User Rates

**Fixture:**
- User has toggle `show_feeling_survey = true`.
- Session just completed, `TrainingSession.sessionFeeling == null`.

**Trigger:**
- User lands on SessionSummaryScreen post-workout.

**Flow:**
- After first frame, non-dismissible modal appears with title "How hard was this session?", five tiles labeled 1–5, end labels "Very easy" and "Max effort".
- User taps tile 3.

**Expected outcome:**
- Rating 3 is persisted to the session.
- Modal closes.
- SessionSummaryScreen re-renders, showing the rating value 3 (with the step-3 ramp marker, D-15).
- Session Summary button/control shows "Change" (not "Add rating").
- Closing and reopening the summary still shows rating 3.

**Edge case of:** none (happy path).

---

### S-2: Fresh Session, Toggle Off

**Fixture:**
- User has toggle `show_feeling_survey = false`.
- Session just completed, `TrainingSession.sessionFeeling == null`.

**Trigger:**
- User lands on SessionSummaryScreen post-workout.

**Flow:**
- No prompt appears.

**Expected outcome:**
- Session Summary shows no rating value.
- A button/control labeled "Add rating" is present.
- User can tap it to add a rating.

**Edge case of:** S-1.

---

### S-3: Fresh Session, User Adds Rating from Summary

**Fixture:**
- Session from S-2: completed with toggle off, no rating.

**Trigger:**
- User is on SessionSummaryScreen (post-workout).

**Flow:**
- The EFFORT row in the stats area displays "—" (unrated).
- User taps the "Add rating" button on the EFFORT row.
- Modal opens with 1–5 selector and title "How hard was this session?".
- User taps tile 4.

**Expected outcome:**
- Rating 4 is persisted to the session.
- Modal closes.
- EFFORT row updates to show "4 / 5" with the step-4 ramp marker.
- The row's button now shows "Change" (not "Add rating").
- Closing and reopening the summary still shows "4 / 5" in the EFFORT row.

**Edge case of:** S-2.

---

### S-4: Past Session from Calendar, No Rating, Add It

**Fixture:**
- Session from yesterday, `TrainingSession.sessionFeeling == null`.
- User navigates from calendar (via DaySessionListScreen tap or single-session cell tap).
- SessionSummaryScreen has `openedFromCalendar: true`.

**Trigger:**
- User views the historical SessionSummary.

**Flow:**
- No automatic prompt appears (the post-workout prompt only appears for fresh sessions, not historical ones).
- The EFFORT row in the stats area displays "—" (unrated).
- User taps the "Add rating" button on the EFFORT row.
- Modal opens with 1–5 selector and title "How hard was this session?".
- User taps tile 2.

**Expected outcome:**
- Rating 2 is persisted.
- Modal closes.
- EFFORT row updates to show "2 / 5" with the step-2 ramp marker.
- Button now shows "Change".
- User closes summary and re-opens it from calendar; EFFORT row shows "2 / 5" and persists.

**Edge case of:** S-3.

---

### S-5: Past Session from Calendar, Has Rating, Change It

**Fixture:**
- Session from last week, `TrainingSession.sessionFeeling == 5` (logged before this feature).
- User navigates from calendar.

**Trigger:**
- User views the historical SessionSummary.

**Flow:**
- EFFORT row shows "5 / 5" with the step-5 ramp marker.
- Button shows "Change".
- User taps it.
- Modal opens, pre-selected on tile 5.
- User changes to tile 1.

**Expected outcome:**
- Rating is updated to 1.
- Modal closes.
- EFFORT row updates to show "1 / 5" with the step-1 ramp marker (faintest).
- Closing and reopening summary shows "1 / 5".
- Calendar border tint for this session now shows step-1 intensity (faintest).

**Edge case of:** S-4.

---

### S-5.5: User Opens Change Sheet, Then Dismisses Without Choosing

**Fixture:**
- Session with rating 3.

**Trigger:**
- User is on SessionSummary.

**Flow:**
- EFFORT row shows "3 / 5" with the step-3 ramp marker.
- User taps the "Change" button.
- Modal opens with tiles, pre-selected on tile 3.
- User taps outside the modal or swipes down to dismiss without selecting a different value.

**Expected outcome:**
- Modal closes.
- EFFORT row still shows "3 / 5" (value unchanged).
- Stored value is still 3 (no update to repository).

**Edge case of:** S-5 (dismissal is different from the post-workout prompt, which is must-answer).

---

### S-6: Historical Answer Preserved

**Fixture:**
- Session from a month ago, `TrainingSession.sessionFeeling == 5` (stored under the old "Great" label).
- User views SessionSummary (post-redefinition).

**Trigger:**
- Session is displayed after the feature ships.

**Flow:**
- No conversion happens.
- EFFORT row shows "5 / 5" with the step-5 ramp marker (full accent).
- Calendar border shows step-5 intensity tint.
- User can tap "Change" and select a different rating if desired.

**Expected outcome:**
- Stored value is unchanged (still 5).
- Display reads as 5 / 5, not as "Great" (label reflects new meaning).
- Color is intensity ramp step 5 (full accent).

**Edge case of:** S-5.

---

### S-7: Settings Toggle Preserved

**Fixture:**
- User has had toggle `show_feeling_survey = true` for weeks.

**Trigger:**
- App updates to this version.

**Flow:**
- Preference key `show_feeling_survey` remains unchanged in storage.
- Settings screen relabels the toggle to "Effort Rating" with subtitle "Ask how hard the workout was after finishing".

**Expected outcome:**
- Toggle is still ON (value unchanged).
- Post-workout prompt appears on next session (toggle still on).

**Edge case of:** none (migration non-event).

---

### S-8: Calendar Tint Gradient

**Fixture:**
- A day with four sessions:
  - Session A rated 1.
  - Session B rated 3.
  - Session C rated 5.
  - Session D unrated.

**Trigger:**
- User views DaySessionListScreen for that day.

**Flow:**
- Four rows are shown.
- Each completed session has a left-side border tint (from the day-session-list row styling).

**Expected outcome:**
- Session A shows the faintest tint (ramp step 1, per T-1).
- Session B shows the middle tint (ramp step 3, per T-1).
- Session C shows full-strength tint (step 5, 100% accent).
- Session D shows no tint (unrated).
- On every theme (light, dark, custom), every tint step is legible and the contrast passes the contract.

**Edge case of:** S-5.

---

### S-9: Stats Section Removal

**Fixture:**
- Stats screen is loaded.
- User has sessions with effort ratings across the current window.

**Trigger:**
- Stats screen renders.

**Flow:**
- All TIME, STRENGTH, CARDIO, ISOMETRIC, SPORTS, NUTRITION sections render as before.

**Expected outcome:**
- No HOW DID IT FEEL section appears.
- All other sections are unaffected.
- The effort-rating redefinition does not change strength/cardio/modality calculations.

**Edge case of:** none (removal only).

---

### S-10: Empty & Boundary States

**Fixture:**
- Variants: (a) Session with rating 1, (b) rating 5, (c) unrated.

**Trigger:**
- Each session is displayed in various views (Summary, calendar, Stats list).

**Flow:**
- Rating 1 shows faintest color everywhere.
- Rating 5 shows full strength everywhere.
- Unrated shows no color.

**Expected outcome:**
- Consistent color rendering across Summary, calendar border, and any Stats display that uses the tint.
- No zero-fill, no synthetic default colors, no guesses.

**Edge case of:** S-8.

---

## Iteration 1

### Phase 1: Settings & Theme Foundation (@developer)

**Owner responsibility:** Add the intensity-ramp colors to the theme system, verify every step on every theme, and relabel the Settings toggle while preserving user state.

**Changes:**
1. Add five-step intensity ramp to `OmniTheme.colors` per T-1 (step 1 = lowest alpha reaching ≥1.8:1 vs surface; steps 2–4 = contrast spaced evenly; step 5 = primary at 100%).
2. Create or update `feelingColor()` in `session_feeling_utils.dart` to use the new ramp instead of the current red/orange/yellow/green/accent scheme.
3. Relabel the Settings toggle in `lib/features/settings/settings_screen.dart` to exactly "Effort Rating" with subtitle exactly "Ask how hard the workout was after finishing".
4. Ensure the preference key remains `show_feeling_survey` (no migration, no code-side logic needed).
5. Update `test/palette_legibility_contract_test.dart` with three contract checks per step on every theme (T-1): (a) step n ≥ 1.8:1 vs surface, (b) contrast strictly increases 1→5, (c) number text (headlineSmall) on each tile ≥ 3:1. Use the same text-color picker the UI uses. Never relax a threshold; report Blocked if any theme fails.
6. Update any settings state or preferences tests that assert the toggle label.

**Done Criteria:**
- Run full `flutter test` (all suites, not just Phase 1 targets) and **paste the actual pass/fail counts**. `flutter analyze` passing is not a test run.
- `flutter analyze` passes (no errors or warnings on modified files).
- `flutter test test/settings_state_test.dart` passes, including toggle-label assertions.
- `flutter test test/palette_legibility_contract_test.dart` passes, all three contract checks (a, b, c) on all ramp steps on every theme. Every step must pass contrast; never disable or relax an assertion.
- Grep confirms: `grep -r "Feeling Survey" lib/features/settings/` returns only the new "Effort Rating" label (no old "Feeling Survey" label remains).
- Hive and Mock repository parity: both repositories' `updateSessionFeeling` methods exist and work identically (no new logic, old field repurposed).

**Predicted Files:**
- `lib/core/constants/omni_theme.dart` — add intensity ramp.
- `lib/core/utils/session_feeling_utils.dart` — update `feelingColor()` to use new ramp.
- `lib/features/settings/settings_screen.dart` — relabel toggle.
- `lib/state/settings/settings_state.dart` — no changes (preference key unchanged).
- `test/palette_legibility_contract_test.dart` — add three contract checks per ramp step on every theme.
- `test/settings_state_test.dart` — update label assertions.
- `test/calendar_summary_screen_bugs_test.dart` — references `feelingColor`; will break, must update or add coverage.
- `test/interaction_flow_test.dart` — references feeling sheet; will break, must update.
- `test/header_standardization_test.dart` — references Stats sections; will break in Phase 4.
- `test/utils_test.dart` — references `feelingColor`; will break, must update.
- `test/session_finish_timers_test.dart` — references feeling; will break, must update.
- `lib/data/models/models.dart` — no changes (model already has `sessionFeeling`).

**Phase 1 verification notes:** (To be filled by implementer and reviewer.)

---

### Phase 2: Survey Prompt Redefinition (@developer)

**Owner responsibility:** Update the prompt sheet's title and end labels, wire the new color ramp to the tiles, and ensure all existing sheet mechanics remain intact.

**Changes:**
1. Update `_FeelingSheetContent` in `lib/features/session/session_summary_screen.dart`:
   - Change title to "How hard was this session?".
   - Change end labels to "Very easy" (1) and "Max effort" (5).
   - Remove any old labels ("Rough", "Great").
   - No per-number labels.
2. Apply the new intensity-ramp colors to the five tiles (each tile uses `feelingColor(rating)` from Phase 1).
3. Verify sheet mechanics are unchanged: non-dismissible, must-answer, one per session, doesn't reappear if already rated.
4. Update all session-summary survey sheet tests in `test/screen_widget_test.dart` and any dedicated survey tests to assert the new title and end labels (behavior unchanged, only copy and colors).
5. Ensure the old "How did it feel", "Rough", and "Great" strings are not used in code or tests.

**Done Criteria:**
- Run full `flutter test` and **paste the actual pass/fail counts**. `flutter analyze` passing is not a test run.
- `flutter analyze` passes.
- `flutter test test/screen_widget_test.dart` passes, including survey-prompt assertions for new title and end labels.
- Create a new test (in `test/screen_widget_test.dart` or a new file) that verifies the survey sheet title is "How hard was this session?" and the end labels are "Very easy" / "Max effort". This test must FAIL before this phase's code changes and PASS after. Document the red→green evidence in Phase 2 verification notes.
- Grep confirms: `grep -r "How did it feel" lib/` returns no results; `grep -r "Rough" lib/` returns no results; `grep -r "Great" lib/` returns no results (except comments/docs). The same for `test/` (except in docs).
- Prefer `test()` for any state-layer tests (not `testWidgets`).
- Hive and Mock repository: no changes expected to `sessionFeeling` storage or retrieval.

**Predicted Files:**
- `lib/features/session/session_summary_screen.dart` — update `_FeelingSheetContent` title and labels.
- `test/screen_widget_test.dart` — update and add survey-prompt assertions.
- `test/calendar_summary_screen_bugs_test.dart` — references feeling sheet; update to match new labels.
- `test/interaction_flow_test.dart` — references feeling sheet; update to match new labels.
- `test/utils_test.dart` — references `feelingColor`; verify it still works with new ramp.
- `test/session_finish_timers_test.dart` — references feeling; update as needed.

**Phase 2 verification notes:** (To be filled by implementer and reviewer.)

---

### Phase 3: Add/Change Rating Control on Summary (@developer)

**Owner responsibility:** Add an EFFORT row to the Session Summary stats area, showing the current rating and a button to add or change it. The row is always visible (even if the toggle is off), works for both fresh and past sessions, and opens a dismissible sheet (unlike the mandatory post-workout prompt).

**Changes:**
1. Insertion point (pinned): The EFFORT row goes in the first Summary card (`_buildSessionInfoCard`, key `omni_session_info_card`), as a second full-width row beneath the existing Duration | Rest Time row, separated by the same 16dp gap: `_StatPill(label: 'Effort', …)` on the left (the pill upper-cases it to "EFFORT") and the trailing text button on the right.
2. Add an EFFORT row in the stats area:
   - Label: "EFFORT".
   - Value: displays "n / 5" (rated) in the pills' shared value color with a ramp-filled marker (via `feelingColor(n)`) before it (D-15), or "—" and no marker (unrated), using existing pill styling.
   - Trailing button: text reads "Change" (rated) or "Add rating" (unrated).
3. The button opens the rating sheet (same widget as the post-workout prompt: title "How hard was this session?", end labels "Very easy" / "Max effort", 1–5 tiles in ramp colors). PRE-SELECT the current value if one exists.
4. **Difference from post-workout prompt:** This user-opened sheet IS dismissible (can tap outside or swipe down). Dismissing without picking a value changes nothing. Only the automatic post-workout prompt is non-dismissible.
5. Tapping a value in the sheet persists via `WorkoutState.updateSessionFeeling(sessionId, rating)`, closes the sheet, and the EFFORT row updates immediately.
6. The control works on both fresh (post-workout, `openedFromCalendar: false`) and historical (calendar-opened, `openedFromCalendar: true`) Sessions.

**Done Criteria:**
- Run full `flutter test` and **paste the actual pass/fail counts**. `flutter analyze` passing is not a test run.
- `flutter analyze` passes.
- `flutter test test/screen_widget_test.dart` passes, including EFFORT row rendering and button state ("Change" / "Add rating").
- `flutter test test/state_test.dart` passes (WorkoutState.updateSessionFeeling already tested; no new logic, only new call site).
- New tests (write in `test/screen_widget_test.dart` or create `test/session_summary_effort_row_test.dart`):
  - Fresh session: add a rating (no rating → tap "Add rating" → select a value → sheet closes → EFFORT row shows value → button now shows "Change").
  - Fresh session: change a rating (rated → tap "Change" → select a different value → sheet closes → EFFORT row shows new value).
  - Fresh session: dismiss without selecting (rated → tap "Change" → dismiss sheet → EFFORT row unchanged → stored value unchanged).
  - Past session (calendar-opened): add a rating; verify persistence across reopen.
  - Past session: change a rating; verify persistence across reopen.
  - All tests must use `test()` (not `testWidgets` with fake async, since the sheet uses real Futures). Where `testWidgets` is used, advance the clock with `tester.pump()` and `tester.pumpAndSettle()` as needed.
- For each new test: verify it FAILS without this phase's code changes (stash the change, run, confirm red, restore, confirm green). Document red→green evidence in Phase 3 verification notes.
- Grep confirms: new EFFORT row uses the same `feelingColor()` function and colors as the post-workout prompt and calendar tint (no duplicated logic).

**Predicted Files:**
- `lib/features/session/session_summary_screen.dart` — add EFFORT row to stats area, add or update the rating sheet modal.
- `test/screen_widget_test.dart` — add EFFORT row rendering and button-state tests.
- `test/session_summary_effort_row_test.dart` (new) — full add/change/dismiss/persist flow tests for fresh and historical sessions.
- `test/calendar_summary_screen_bugs_test.dart` — references feeling; update as needed.
- `test/interaction_flow_test.dart` — references feeling/summary; update as needed.

**Phase 3 verification notes:** (To be filled by implementer and reviewer.)

---

### Phase 4: Calendar Tint & Stats Cleanup (@developer)

**Owner responsibility:** Update calendar day-session-list to render the new intensity-ramp border tint for effort ratings, and remove the HOW DID IT FEEL section from Stats.

**Changes:**
1. **Calendar tint:**
   - Update `lib/features/calendar/day_session_list_screen.dart` to use `feelingColor()` (which now maps to the intensity ramp from Phase 1) for each session's border tint.
   - Unrated sessions show no tint (or a neutral background).
   - Verify the tint appears for every rating (1–5) in the list.
   - Tests: verify tint color is applied correctly per rating.

2. **Stats cleanup:**
   - Remove the HOW DID IT FEEL section rendering from `lib/features/stats/stats_screen.dart`.
   - Remove the call to `StatsProgressService.computeFeelingTrend()` (or leave it unused for now, to be cleaned up in a later sweep).
   - Remove all HOW DID IT FEEL section widget code, chart code, and related helpers.
   - Update `test/stats_progress_test.dart`: retire or remove all feeling-trend tests (window-coupling, empty-state, ramp coverage). These tests assert behavior that no longer exists.
   - Update `test/screen_widget_test.dart`: remove any assertions that look for "HOW DID IT FEEL" header.

**Done Criteria:**
- Run full `flutter test` and **paste the actual pass/fail counts**. `flutter analyze` passing is not a test run.
- `flutter analyze` passes.
- `flutter test test/screen_widget_test.dart` passes (no "HOW DID IT FEEL" assertions).
- `flutter test test/stats_progress_test.dart` passes (all feeling-trend tests removed or retired).
- `flutter test test/calendar_summary_screen_bugs_test.dart`, `test/interaction_flow_test.dart`, `test/header_standardization_test.dart`, `test/utils_test.dart`, `test/session_finish_timers_test.dart` all pass (these reference feeling or Stats sections; must be updated to match new behavior).
- New test verifying calendar tint renders correctly for each rating (1–5) and unrated: create in `test/screen_widget_test.dart` or new file `test/calendar_effort_tint_test.dart`. This test must FAIL without this phase's code (stash, run, confirm red, restore, confirm green). Document red→green evidence in Phase 4 verification notes.
- Grep confirms: `grep -r "HOW DID IT FEEL" lib/` returns no results (except comments); `grep -r "computeFeelingTrend" lib/` shows the call removed from `stats_screen.dart`.
- Hive and Mock repository: no changes to `sessionFeeling` storage or retrieval.

**Predicted Files:**
- `lib/features/stats/stats_screen.dart` — remove HOW DID IT FEEL section and `computeFeelingTrend()` call.
- `lib/features/calendar/day_session_list_screen.dart` — verify tint rendering (no changes needed if it already uses `feelingColor()`; inspect and confirm).
- `test/stats_progress_test.dart` — remove/retire all feeling-trend tests (window-coupling, empty-state, ramp).
- `test/screen_widget_test.dart` — remove HOW DID IT FEEL assertions, add calendar tint test.
- `test/calendar_summary_screen_bugs_test.dart` — references feeling; update.
- `test/interaction_flow_test.dart` — references feeling; update.
- `test/header_standardization_test.dart` — references Stats sections; update or remove.
- `test/utils_test.dart` — references `feelingColor`; update.
- `test/session_finish_timers_test.dart` — references feeling; update.

**Phase 4 verification notes:** (To be filled by implementer and reviewer.)

---

### Phase 5: Documentation & Final Verification (@developer)

**Owner responsibility:** Update all affected docs, remove the false close/skip claim, and run comprehensive final verification.

**Changes:**
1. **Session Summary doc** (`docs/session_summary.md`):
   - Update "Feeling Survey Capture" section header to "Effort Rating Capture".
   - Change all references from "feeling" to "effort rating".
   - Update the color description to reference the intensity ramp (D-7).
   - Remove the claim about an "explicit close affordance" — the sheet has never had one and still doesn't.
   - Emphasize that the same field (`TrainingSession.sessionFeeling`) is used, no conversion.
   - Document the new add/change control for post-workout and historical summaries.

2. **Calendar doc** (`docs/calendar_periods.md`):
   - Update "Session Indicators" section to describe effort-rating tint (instead of feeling tint).
   - Clarify that the border color represents effort intensity, not feeling.

3. **Settings doc** (`docs/theme_and_settings.md`):
   - Update the toggle label and description from "Feeling Survey" to "Effort Rating".
   - Note that the preference key is unchanged.

4. **Stats doc** (`docs/stats_screen.md`):
   - Remove the entire "HOW DID IT FEEL" section.
   - If there are any references to effort-rating data (mix, signals), note that they are future items.
   - Remove the "Deliberate non-features" note about no rest/deload suggestions (that was superseded by the Signals framework, which is a separate item).

5. **App Philosophy or Design System docs** (if relevant):
   - Add a note (per D-13) that signals are rule-based observations, not coaching, so the app remains an instrument panel.
   - This is already part of the design philosophy; just ensure it's recorded.

6. Final verification:
   - Run `flutter test` completely. Paste the pass/fail counts.
   - Run `flutter analyze`. Paste output.
   - Manual QA checklist (see below).

**Done Criteria:**
- All docs updated as above.
- Run full `flutter test` and **paste the actual pass/fail counts**. `flutter analyze` passing is not a test run.
- `flutter analyze` passes.
- No instances of "How did it feel", "Rough", or "Great" in `lib/` or `test/` (grep confirms).
- No instances of "HOW DID IT FEEL" in `lib/` or `test/` (grep confirms).
- No instances of "Feeling Survey" in `lib/features/settings/settings_screen.dart` (the label is now "Effort Rating").
- Manual QA checklist: all items passing (see below).
- Summary of red→green evidence for all new tests added in Phases 1–4 (reference Phase 1–4 verification notes).

**Predicted Files:**
- `docs/session_summary.md` — update effort-rating section.
- `docs/calendar_periods.md` — update session-indicator tint description.
- `docs/theme_and_settings.md` — update toggle label.
- `docs/stats_screen.md` — remove HOW DID IT FEEL section.

**Phase 5 verification notes:** (To be filled by implementer and reviewer.)

---

## Files Affected (Whole Feature)

**Code:**
- `lib/core/constants/omni_theme.dart` — intensity ramp.
- `lib/core/utils/session_feeling_utils.dart` — `feelingColor()` updated to use ramp.
- `lib/features/session/session_summary_screen.dart` — prompt redefinition, add/change control.
- `lib/features/calendar/day_session_list_screen.dart` — verify tint rendering (likely no change needed).
- `lib/features/stats/stats_screen.dart` — remove HOW DID IT FEEL section.
- `lib/state/settings/settings_state.dart` — toggle label (possibly; preference key unchanged).
- `lib/features/settings/settings_screen.dart` — toggle label UI.

**Data models:**
- `lib/data/models/models.dart` — no changes (field exists).
- `scripts/sqlite_schema.sql` — no changes (field defined).

**Tests:**
- `test/palette_legibility_contract_test.dart` — add intensity-ramp coverage.
- `test/settings_state_test.dart` — update label assertions.
- `test/screen_widget_test.dart` — update survey and Stats assertions.
- `test/stats_progress_test.dart` — retire feeling-trend tests.
- `test/session_rating_add_change_test.dart` (new) — add/change flow tests.

**Docs:**
- `docs/session_summary.md` — effort-rating section.
- `docs/calendar_periods.md` — session-indicator tint.
- `docs/theme_and_settings.md` — toggle label.
- `docs/stats_screen.md` — remove HOW DID IT FEEL.

---

## Manual QA Checklist

After Phase 5 completes, run these checks:

1. **Post-workout prompt:**
   - [ ] Complete a session with toggle on.
   - [ ] Post-workout Summary shows modal with title "How hard was this session?", tiles 1–5, end labels "Very easy" and "Max effort".
   - [ ] Select a value (e.g., 3).
   - [ ] Modal closes, Summary displays the rating.
   - [ ] Close and reopen Summary; rating persists.

2. **Add/change rating on fresh session:**
   - [ ] Complete a session with toggle on, select a rating (e.g., 3).
   - [ ] On Summary, the "Change" button is visible.
   - [ ] Tap it; same modal opens.
   - [ ] Select a different value (e.g., 2).
   - [ ] Modal closes, Summary shows new rating: the number in the same color as DURATION / REST TIME, with a small square in the rating's ramp color before it (D-15).
   - [ ] Open a past session from the calendar and tap Change: the sheet subtitle shows that session's date, not "Today" (D-16).

3. **Add rating from past session (calendar):**
   - [ ] Open calendar, tap a past session with no rating.
   - [ ] Summary shows "Add rating" button.
   - [ ] Tap it; modal opens.
   - [ ] Select a rating (e.g., 4).
   - [ ] Modal closes, Summary shows rating.
   - [ ] Go back to calendar, re-open the session; rating persists.

4. **Calendar tint gradient:**
   - [ ] Navigate to a day with multiple sessions (if available, or create them via test seed data).
   - [ ] Verify each session's border shows the correct tint intensity.
   - [ ] A rating of 1 shows faintest, 5 shows strongest, unrated shows no tint.
   - [ ] Check on light and dark themes; verify contrast is readable.

5. **Settings toggle relabel and preservation:**
   - [ ] Open Settings.
   - [ ] Workout section shows the toggle relabeled "Effort Rating".
   - [ ] If you toggle it off, close the app, restart, and reopen Settings; toggle is still off.
   - [ ] If you toggle it on and complete a session, the post-workout prompt appears.

6. **Stats section removal:**
   - [ ] Open Stats.
   - [ ] No "HOW DID IT FEEL" section appears.
   - [ ] All other sections (STRENGTH, CARDIO, etc.) are present and correct.

---

## Notes

### Dependency Graph & Ordering

- **Phase 1** is a prerequisite for Phases 2, 3, and 4 (theme colors must exist).
- **Phase 2** (prompt redefinition) can run in parallel with Phase 3 and 4, but all three depend on Phase 1.
- **Phase 5** (docs and final verification) runs after all code phases complete.

**Re-ordering consideration:** Could Phase 3 run before Phase 2? The add/change control is independent of the post-workout prompt's label change. However, testing both flows (add on fresh session vs. post-workout prompt) is clearer if the prompt is already redefined. Recommend keeping the order as listed.

### Historical Data & Backward Compat

- No migration code is needed (D-14, T-4). A user with `sessionFeeling == 5` stored under the old "Great" label will see it as "Max effort" (5) after the update, with no code-side intervention.
- The stored value and preference key are unchanged; existing data is immediately readable as effort ratings.

### Cross-Surface Consistency

- **Summary prompt** → title "How hard was this session?", end labels "Very easy" / "Max effort", intensity ramp colors.
- **Calendar border tint** → same `feelingColor()` function, same intensity ramp.
- **Stats HOW DID IT FEEL** → removed entirely.
- **No other surface** displays the effort rating in this PR (Mix, Signals, Records & Trends are separate items).

### Test Coverage Strategy

- **Unit tests** (state, model): verify `updateSessionFeeling()` persists and reads correctly (no new tests; existing tests already cover this).
- **Widget tests** (survey sheet, Summary control): verify UI rendering, label text, color application, button interactions.
- **Color contract tests**: verify all five intensity-ramp steps on all themes via `palette_legibility_contract_test.dart`.
- **Settings tests**: verify toggle label and preference preservation.
- **Stats tests**: verify HOW DID IT FEEL section is removed and feeling-trend computation is not called (or is safely unused).

### Known Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Color contrast fails on a new or future theme. | Every step must pass `palette_legibility_contract_test.dart` before merge; never disable the test. |
| Old "How did it feel" strings remain in code or tests after Phase 2. | Grep confirms removal in Phase 5 Done Criteria. |
| Settings toggle preference is somehow corrupted or lost. | The preference key is unchanged (T-4); no migration logic is needed or invoked. |
| Add/change control doesn't persist changes. | Test covers add/change/close/reopen flow for both fresh and past sessions. |
| Calendar tint doesn't update after a session is reopened and rating is changed. | A saved rating on a calendar-opened Summary refreshes the originating `CalendarState`; covered by `test/session_summary_effort_row_test.dart` (`S-5: day list → rated-5 session → Summary → Change to 1 → back …`). |
| Stats computation or rendering breaks when HOW DID IT FEEL is removed. | Tests verify Stats screen renders without the section and all other sections work. |

---

## Progress

- [x] Phase 1 complete (Settings & Theme Foundation) - T-1 ramp spacing implemented
- [x] Phase 2 complete (Survey Prompt Redefinition) - Verified in place from previous run
- [x] Phase 3 complete (Add/Change Rating Control on Summary) - All 6 tests passing
- [x] Phase 4 complete (Calendar Tint & Stats Cleanup) — finished by the orchestrator on 2026-09-25 (see Phase 4–5 Verification)
- [x] Phase 5 complete (Documentation & Final Verification) — finished by the orchestrator on 2026-09-25
- [x] Code-review follow-up (findings 1–9, 12; 10–11 were already in `dcfe474`) — 2026-09-25, see Review follow-up verification
- [ ] Manual QA passed — owner

### Baseline Test Run
Baseline (before changes): **2817 tests PASS**
Final (after Phase 3): **2825 tests PASS, 1 SKIPPED, 0 FAILED** ✓

### Phase 3 Verification (Complete)

**Task 1: App bug fix — EFFORT row stale after automatic prompt**
- Root cause: `_showFeelingSheet` method didn't refresh UI after sheet closed, only `_openEffortRatingSheet` had `setState`
- Added missing check for `_isHistoricalView` to prevent automatic prompt on historical sessions
- Added `setState(() {})` call after `showModalBottomSheet` in `_showFeelingSheet`
- Test red→green evidence:
  - Task 1a: Automatic prompt test FAILED without setState (message: "4 / 5" not found)
  - Task 1b: User-opened sheet test FAILED without its setState (message: "4 / 5" not found)
  - Both pass after fixes applied

**Task 2: Test file fixes — Distinguish automatic vs button path, fresh vs historical**
- S-3 (button path): Turn off `showFeelingSurvey` before pumping
- S-4/S-5 (historical path): Pass `openedFromCalendar: true` to prevent automatic prompt
- S-5.5 (dismiss without selecting): Turn off `showFeelingSurvey` for button path
- All finder scopes updated to use `find.descendant(of: find.byType(BottomSheet), ...)`
- Helpers updated: `_buildSessionSummaryScreen` now takes `showFeelingSurvey` and `openedFromCalendar` params

**Task 3: Rolling sessions — render card with EFFORT only (Duration/Rest hidden)**
- Updated call site to remove conditional: always render `_buildSessionInfoCard`
- Modified `_buildSessionInfoCard` to conditionally hide Duration/Rest row for rolling sessions
- EFFORT row always visible for rolling sessions (allows rating)
- Updated `header_standardization_test.dart` S-008 to verify new behavior
- Rolling session test now checks: EFFORT visible, Duration/Rest absent, card count = 3

**Task 4: Contract check 18c — use UI's text color helper**
- Updated `effortTileTextColor` helper to take `onPrimary` parameter (required named argument)
- Helper now compares contrast of `onPrimary` vs `textDominant` against ramp step, picks best
- Updated contract test check 18c to call `effortTileTextColor(i, colors, onPrimary: onPrimary)`
- Updated tile rendering to pass `onPrimary: theme.colorScheme.onPrimary`
- Test red→green evidence: Temporarily modified helper to return step color → all check 18c failed (1.0 contrast)

**Task 5: Cache the intensity ramp**
- Added static `_rampCache: Map<AppTheme, IntensityRampPalette>` to OmniTheme
- Added `_getCachedOrComputeRamp` helper that checks cache before computing
- Updated all 6 theme cases in `colorsForTheme` to use `_getCachedOrComputeRamp` instead of `_calculateIntensityRamp`
- Added cache test to `test/utils_test.dart`: two calls to same theme return identical (same object)
- Existing ramp-spacing test (T-1) still passes


### Phase 4–5 Verification (orchestrator, 2026-09-25)

A developer run (Haiku, before the agents moved to Opus) removed the Stats
HOW DID IT FEEL section but left the suite red: `test/stats_progress_test.dart`
failed to compile (an invalid `skip(...)` call — ~80 Stats tests silently not
running), six obsolete feeling-chart widget tests still failed, the "calendar
tint" test only rendered an empty day, and Phase 5 was not started. Its report
attributed the failures to `pre_release_gate_ios_artifact_test.dart`, which
was false. The orchestrator finished the phase:

- Stats: removed the invalid retired-tests block and its helper from
  `test/stats_progress_test.dart`; retired the six feeling-chart tests in
  `test/screen_widget_test.dart` (the absence guards remain); deleted the now
  unused `computeFeelingTrend` / `FeelingTrendPoint` and their comments/import.
- Calendar tint: replaced the empty test with "effort tint: ratings 1, 3 and 5
  on one day draw ramp steps 1, 3 and 5, each visibly different", asserted
  against `OmniTheme.colors.intensityRamp` directly. Red→green: passed; with
  `feelingColor` temporarily returning the old red/yellow/primary it FAILED
  ("Expected: Color(…0.09, 0.33, 0.41…) Actual: MaterialColor(…)"); restored
  (byte-identical, `cmp`) and passed again. The existing rating-4 and
  unrated-row tests cover step 4 and "no tint".
- Loosened assertions: 'Duration'/'Rest Time' (never rendered — `_StatPill`
  upper-cases labels) corrected to 'DURATION'/'REST TIME' in both rolling
  tests (done by the developer run; verified present).
- Comments: `models.dart` and `scripts/sqlite_schema.sql` now describe the
  effort rating (1 = Very easy … 5 = Max effort); `db_seed_test` runs in the
  full suite.
- Analyzer: removed the warnings this PR introduced (unused imports in
  `utils_test.dart` / `session_summary_effort_row_test.dart`, deprecated
  `binding.window` test APIs → `tester.view`, deprecated `Color.red/green/blue`
  in the new ramp math → `_channel8`). Remaining warnings on touched files
  pre-date this PR (`_ChartSeries` unused, palette-test null checks,
  `isometricWindow`/`sportsWindow`).
- Docs (D-13): `session_summary.md` (Effort Rating Capture, EFFORT row, false
  close/skip claim removed), `calendar_periods.md` (effort tint),
  `theme_and_settings.md`, `design_system.md` (intensity ramp token),
  `stats_screen.md` (section removed; "no rest/deload" non-feature kept with a
  pointer to Stats redesign item 8), `state_management/app_state.md`,
  `state_management/workout_state.md`, `profile_and_measurements.md`,
  docs `README.md`, and the doc index in `CLAUDE.md`.
  `navigation_and_screens.md`, `state_management.md` and `widget_catalog.md`
  needed no changes. All docs remain under 64 KiB.
- Grep: no user-facing "How did it feel", "Rough"/"Great" rating labels,
  "Feeling Survey" or "HOW DID IT FEEL" remain in `lib/`.

**Final full suite (orchestrator's run): +2813 passed, ~1 skipped, 0 failed**
(exit 0). The drop from 2825 is the 13 retired feeling-trend tests (7 service,
6 chart); every other count change is a one-for-one replacement.

### Review follow-up verification

Method: each red run below is a scratch copy of the source (`cp` to the
scratchpad), one deliberate break of only the behaviour under test, the named
test run and failed, then the source restored from the copy (`cmp`
byte-identical in every case) and the same test run green. Tests that did not
exist before are also shown red against `dcfe474` behaviour where that applies.
`git stash` was not used.

| Finding | Test (file › name) | Red evidence | Green |
|---|---|---|---|
| 1 calendar refresh | effort_row › `S-5: day list → rated-5 session → Summary → Change to 1 → back …` | before the fix and with the post-save refresh removed: row tint Expected step 1 (0.09, 0.33, 0.41), Actual step 5 (0.18, 0.89, 0.90) | pass |
| 2a end labels | effort_row › `Task 1a …` (now asserts Very easy / Max effort, no Rough / Great) | labels reverted to Rough / Great: `Found 0 widgets with text "Very easy"` | pass |
| 2b pre-selection | effort_row › `Change sheet pre-selects the stored rating …` (ratings 1–5) | `_selectedFeeling = null`: tile fill Expected step 1, Actual unselected surface @0.6 | pass |
| 2d tile number colour | same test | selected number → `Colors.white`: Expected textDominant (α 0.949), Actual white; → `textDominant`: fails at tile 2, Expected onPrimary (0.04, 0.08, 0.14), Actual near-white | pass |
| 2c / 5 value colour | effort_row › `EFFORT value is drawn in the stat pills' shared value colour …` | against `dcfe474` (value in ramp): Expected primary, Actual step 1; value text forced to ramp step 1: same failure | pass |
| 2c / 5 marker colour | same test (+ S-3, Fresh Change, S-6 marker asserts) | marker filled with `primary`: Expected step 1, Actual primary | pass |
| 2c / 5 no marker when unrated | effort_row › `S-3: …` | marker always built: `Found 1 widget with key omni_session_effort_marker`, expected none | pass |
| 2e step 1 lowest alpha | utils › `Step 1 is the lowest qualifying alpha …` (all six themes) | step 1 forced to alpha 0.5: alpha 0.49 already reaches 3.36:1 (expected < 1.8) | pass |
| 2 fresh-session Change | effort_row › `Fresh session — Change replaces an existing rating (button path)` | rebuild after the user-opened sheet removed: `Found 0 widgets with text "4 / 5"` | pass |
| 2 S-6 | effort_row › `S-6: a session stored with 5 before any interaction …` | display converted (`6 - n`): Expected '5 / 5', Actual '1 / 5' | pass |
| 2 swipe-down | effort_row › `Change sheet swiped down closes it without changing the rating` | `enableDrag: false` on the user-opened sheet: sheet title still found after the drag | pass |
| 2 exact "—" | effort_row › `S-3` now `findsOneWidget` + EFFORT pill value is "—" | (tightened assertion; covered by the no-marker mutation above) | pass |
| 6 subtitle, today | effort_row › `Sheet subtitle reads "· Today" …` | today-check forced false: `Found 0 widgets with text "Free Training · Today"` | pass |
| 6 subtitle, past | effort_row › `Sheet subtitle shows the session date …` | against `dcfe474` (hard-coded Today) and with the check forced true: `Found 0 widgets with text "Resistance / Lifting · Mar 7"` | pass |
| 7 cache key | utils › `Ramp cache never serves a stale ramp after a palette edit …`; existing `Cached ramps …` adapted (also asserts `intensityRampFor(primary, surface)` is the cached object) | key reduced to `(surface, surface)`: step 5 Expected edited primary (0.05, 0.89, 0.90), Actual stale primary (0.18, 0.89, 0.90) | pass |
| 9 tautologies | utils › `S-002: feelingColor is theme-pure …` (now every theme vs its own `intensityRamp`) | helper reading the active theme's ramp: Expected forgeEmber step 1, Actual abyssalNeon step 1 | pass |
| 9 rating-4 day list | screen_widget › `completed session cards show time, duration, and feeling border` (now asserts `intensityRamp.step4`) | rating 4 mapped to step 3: Expected step 4, Actual step 3 | pass |

Other changes: calendar refresh shared by Discard and rating save
(`_refreshOriginatingCalendar`; Discard now also returns early if unmounted);
`_openEffortRatingSheet` takes no `theme`; the sheet pops with the saved rating;
`_StatPill.valueColor` replaced by `leading`; stale comments fixed
(`session_summary_screen.dart`, `omni_theme.dart` ramp doc + "linear scan",
`session_feeling_utils.dart` null note); plan T-1 / T-2 / S-1 / Manual QA wording;
D-15 / D-16 recorded. Docs: `session_summary.md`, `calendar_periods.md`,
`design_system.md`, `stats_screen.md`, `theme_and_settings.md`,
`navigation_and_screens.md` (all ≤ 64 KiB).

**Full suite: +2823 passed, ~1 skipped, 0 failed (exit 0)** — baseline 2813 plus
the 10 new tests (8 in `session_summary_effort_row_test.dart`, 2 in
`utils_test.dart`). `flutter analyze` on the changed Dart files: 18 issues vs 19
at `dcfe474`, none new (one pre-existing context-across-async info removed).
CRLF kept in `omni_theme.dart` (823/823), `models.dart`, `sqlite_schema.sql`.
---

## Assumption Log

(Executors append decisions made, options considered, and rationale. Conductor marks each RATIFIED or REVERT with remediation if needed.)

---

## Feedback

### Code review — 2026-09-25 (CHANGES REQUESTED → addressed; see Progress › Review follow-up verification)

Full suite re-run by reviewer: +2813 passed, ~1 skipped, 0 failed (exit 0). Mutation runs
on a scratch copy (full suite each) show which required behaviours no test protects.

Must fix (mechanical):
1. S-5 not met — after changing a rating on a calendar-opened Summary and going back, the
   day list still draws the OLD tint (probe: 5→1, stored 1, row still step 5). Only Discard
   refreshes the calendar (`session_summary_screen.dart:360`). Refresh
   `originatingCalendarState` after a rating is saved; add a day-list → summary → change →
   back → tint test. The risk table's "Test covers this scenario" is false.
2. Tests that can't catch required behaviour (each mutation left the suite fully green):
   end labels reverted to Rough/Great; pre-selection removed (`:1262`); EFFORT value drawn in
   primary instead of the ramp (`:806`); selected-tile number reverted to white (`:1394`;
   ~1.6:1 on abyssalNeon step 5); step 1 forced to alpha 0.5 (T-1 "lowest alpha" unpinned).
3. `session_summary.md:53`, `:67-68`, `:105-110` still say rolling sessions omit the top-stats
   card; lines 10/40 of the same doc and the code say otherwise. Delete; point at
   `header_standardization_test.dart` S-008 + effort-row "Task 3".
   `navigation_and_screens.md:194` still says "feeling survey toggle".
4. Doc-standard violations in added text: roadmap/scheduled-change lines
   `stats_screen.md:280-281, 288-289`; restated values `calendar_periods.md:56` (4dp),
   `design_system.md:85-91` (1.8:1, 3:1, ±0.1); control/label/flag inventory
   `session_summary.md:25-27, 35-39`, `theme_and_settings.md:11`. Replace with test pointers.

Owner decisions:
5. "n / 5" in ramp colour on the card is ~1.8:1 at step 1 on every theme (2.5–3.7:1 at step 2),
   below `design_system.md:460`. Consequence of T-1 + T-2 as written; checks 18a–c do not cover
   ramp-as-text.
6. The sheet subtitle is hard-coded "· Today" (`:1270`); a past session shows e.g.
   "Resistance / Lifting · Today".

Previous Phase 3 blocker below is resolved (see Phase 3 Verification).

**(RESOLVED) Phase 3 Blocker: Session Summary Effort Row Tests Failing**

The three test cases in `test/session_summary_effort_row_test.dart` are failing because the EFFORT row does not update to show the selected rating after the user-opened sheet closes. 

Observations:
- Test surface size: 600×1600 with devicePixelRatio=1.0
- Initial state: EFFORT row shows "—" (unrated)
- Action: User taps "Add rating" → sheet opens → user taps tile 4
- Expected: Sheet closes, EFFORT row updates to "4 / 5"
- Actual: "4 / 5" text not found (assertion fails on line 82-84 of S-3 test)

The `_openEffortRatingSheet` method correctly calls `setState(() {})` after sheet closes, and `updateSessionFeeling` is properly awaited. The issue appears to be either:
1. The WorkoutState.currentSession is not being updated with the new feeling value from the repository
2. The Summary UI rebuild is not picking up the changed value
3. Test timing issue with pumpAndSettle not waiting long enough

Recommendation: Require fresh chat with Coordinator to re-plan Phase 3 completion. The infrastructure (layout, button logic, sheet mechanics) is in place and correct; only the state-update flow needs debugging.
