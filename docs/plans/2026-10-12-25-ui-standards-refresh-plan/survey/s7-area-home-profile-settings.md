# S7 pointer sheet — area: home, calendar, periods, profile, settings, onboarding, splash, startup

Read-only scout. Docs compared: `docs/app_philosophy.md`, `docs/widget_catalog/home_screen.md`,
`docs/calendar_periods.md`, `docs/profile_and_measurements.md`, `docs/theme_and_settings.md`,
`docs/navigation_and_screens.md`, `docs/widget_catalog/feature_primitives.md`, plus
`docs/docs-audit-2026-07-26.md` §8.1 (hub question). Code compared: `lib/features/{home,calendar,period,profile,settings,onboarding,splash,startup}`
and the shared widgets they pull from `lib/widgets/`, `lib/core/`, `lib/state/`.

Names checked against `lib/`: 41 doc-named symbols/screens — EnergyTile, EnergyCore, MaintenanceTile,
NutritionSummaryCard, CalorieRing, CalorieRingCard, WaterTrackerControl, MacroDonutChart,
MacroFocusContent, AvatarCropSheet, MeasurementSparkline, HomeLogoButton, AnimatedZenHalo,
ZenHaloPainter, OmniCardHeader, OmniSurface, OmniBackHeader, OmniBottomCTA, ScrollableTrendChart,
ConfirmationDialog, OmniNavigator, OmniRoute, OmniFadeRoute, OmniGradientBackground,
MetricChooserDialog, ModalityPickerDialog, AppVersionInfo/formatVersionLine, kWaterGlassMl,
foodsIEatSections, feelingColor, ModalityColorUtils, AppTheme (6 values), HomeTiles.all (6 tiles),
ProfileMeasurements.additional (8 rows, doc order matches), PeriodState.validate
(nameError/dateError/overlapError), StartupPreparingScreen, StartupFailureScreen, OmniSplashScreen,
OnboardingScreen, MaintenancePlaceholderScreen, HubSheet (absent — see C1). All exist as documented
except where a finding below says otherwise. Not individually checked: `_FoodLibraryBrowseSection`
(private to nutrition_screen.dart — outside this area's screens; the doc itself marks it private).

Screen-map check: every screen in `navigation_and_screens.md`'s Screen Inventory exists at its stated
path. Every screen file under this area's `lib/features` appears in the inventory EXCEPT
`lib/features/startup/startup_preparing_screen.dart` (S6 below). The "two conflicting hub
implementations" question is C1 below.

---

## Findings

### C1 · CONFLICT · Audit doc still describes a second hub implementation that the code (and the screen doc) say was deleted
- Where the doc says it: `docs/docs-audit-2026-07-26.md:190`
  ```
  ### 8.1 Two hub implementations disagree
  *Flagged in `navigation_and_screens.md` under "Unresolved: two hub
  implementations".*
  | `HubSheet` (`lib/widgets/hub/hub_sheet.dart`) | 5 — adds Nutrition | **No — never instantiated** |
  ```
  `docs/plans/docs-standard-audit-2026-07-30.md:206` repeats it ("`HubSheet` is never instantiated").
- Where the code does it: searched `class HubSheet|HubSheet\(` across `lib/` — only
  `lib/features/home/home_screen.dart:319` (`void _openHubSheet() {`) and `:430`
  (`HomeLogoButton(onTap: _openHubSheet)`) match, both method names, no class. `lib/widgets/hub/`
  does not exist (glob over `lib/widgets/` found no hub directory).
- What a user would see: nothing — there is one hub sheet, built by `_buildMaintenanceGrid`, with
  five destinations (Profile, Stats, Calendar, Settings, Exercise Library; quoted at `home_screen.dart:1131-1213`).
- Guard: none found: searched `hub_interaction_test` — not checked whether the file still exists.
- Unsure: whether `test/hub_interaction_test.dart` still exists (did not glob test/).

### S1 · STALE-DOC · Maintenance-sheet snap points in app_philosophy do not match the code
- Where the doc says it: `docs/app_philosophy.md` §8
  ```
  The sheet snaps directly between collapsed (7%) and expanded (92%); the previous mid snap point was removed so opening the sheet is a single-step gesture.
  ```
- Where the code does it: `lib/features/home/home_screen.dart:131-132` and `:957-962`
  ```
  static const double _minSheetExtent = 0.0;
  ...
  const hubSheetMaxExtent = 0.95;
  _maxSheetExtent =
      ((mq.size.height - mq.padding.top - appBarToolbarHeight) /
              mq.size.height)
          .clamp(0.5, hubSheetMaxExtent);
  ```
  Snap sizes are `[_minSheetExtent, _maxSheetExtent]` (`home_screen.dart:975`).
- What a user would see: the collapsed sheet rests fully hidden (0%), and the expanded cap is a
  computed fraction clamped to 0.95 — not the fixed 7%/92% the doc states.
- Guard: none found for the doc numbers; `home_screen.dart:58` says the header gap is "Pinned by
  `home_logo_hub_open_test.dart`" (not checked).
- Unsure: nothing else.

### S2 · STALE-DOC · app_philosophy says onboarding collects data and seeds defaults; the screen collects nothing
- Where the doc says it: `docs/app_philosophy.md` §11
  ```
  Onboarding collects only what changes the app's defaults — training type, goal, and available
  equipment — and uses it to seed the default SportProfile, initial Templates, and home category
  ordering.
  ```
- Where the code does it: `lib/features/onboarding/onboarding_screen.dart:80-160` — three PageView
  pages (`_buildWelcomePage`, `_buildHowYouTrainPage`, `_buildHowYouPlanPage`), no TextField, no
  question, no state writes. Completion is only:
  ```
  await widget.repository.setPreferenceBool('onboarding_complete', true);
  ```
  (`onboarding_screen.dart:98`).
- What a user would see: a read-only three-page intro; nothing they pick changes any default,
  because there is nothing to pick.
- Guard: none found: searched `onboarding` in test/ — not checked.
- Unsure: whether any seeding happens elsewhere (searched `lib/features/onboarding` only).

### S3 · STALE-DOC · navigation doc describes a resume prompt; the home screen restores silently
- Where the doc says it: `docs/navigation_and_screens.md` "Active Session Resume"
  ```
  - **Dismissing the resume prompt is not a delete.** System back-dismiss must preserve the stored
    session; only an explicit confirmed discard deletes it.
  - **Only the most recent dangling session is surfaced**; older ones are cleaned up by state.
  Verified by `test/interaction_flow_test.dart`.
  ```
- Where the code does it: `lib/features/home/home_screen.dart:186-193`
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
  No prompt/dialog is shown on Home for a dangling session (the only two dialogs on Home are the
  "Start New Session?" conflict dialogs, `home_screen.dart:683-696` and `:758-773`). The test name
  agrees: `test/interaction_flow_test.dart:159` "cold-start loaded session shows active tile without
  launch modal and tap resumes".
- What a user would see: after a force-kill mid-session the app opens straight onto Home with the
  matching tile already active; no modal asks whether to resume.
- Guard: `test/interaction_flow_test.dart:159` (test name quoted above) — it pins the silent
  behaviour, so the doc, not the code, is stale.
- Unsure: whether some other surface shows a resume prompt (searched `lib/` for "Resume"/"dangling";
  only watch and timer code matched).

### S4 · STALE-DOC · navigation doc contradicts itself about the legacy placeholder
- Where the doc says it: `docs/navigation_and_screens.md` Screen Graph section
  ```
  The legacy bottom "Edit Targets" button is gone. The legacy placeholder no longer exists.
  ```
  versus the same document's Non-Production Screens table:
  ```
  | `MaintenancePlaceholderScreen` | `lib/features/home/maintenance_placeholder_screen.dart` | Dead code. Zero references anywhere in `lib/` or `test/`. ... |
  ```
- Where the code does it: `lib/features/home/maintenance_placeholder_screen.dart:4` — the class
  exists; searched `MaintenancePlaceholderScreen` across `lib/`: only its own file matches (zero
  call sites in `lib/`; `test/` not checked).
- What a user would see: nothing (unreachable), but the doc says both "gone" and "exists as dead code".
- Guard: none.
- Unsure: whether test/ references it (doc claims zero there too; not checked).

### S5 · STALE-DOC · Day list grouping: doc says two groups, code renders three
- Where the doc says it: `docs/calendar_periods.md` "Day Session List"
  ```
  `DaySessionListScreen` groups entries into Completed first, then Planned.
  ```
  and UX Rules Snapshot #3: "Day list is grouped: Completed first, Planned second."
- Where the code does it: `lib/features/calendar/day_session_list_screen.dart:129-176` — sections
  render in order `Completed`, `Planned`, then:
  ```
  if (inProgress.isNotEmpty) ...[
    const SizedBox(height: 12),
    const _SectionHeader(title: 'In Progress'),
  ```
- What a user would see: a third "In Progress" group at the bottom of the day list that no doc mentions.
- Guard: none found: searched `In Progress` in test/ — not checked.
- Unsure: nothing else.

### S6 · STALE-DOC · StartupPreparingScreen is missing from the Screen Inventory
- Where the doc says it: `docs/navigation_and_screens.md` Screen Inventory — no row for
  `StartupPreparingScreen`; it is described only in the App Entry Point prose ("the neutral
  preparation surface (`lib/features/startup/startup_preparing_screen.dart`) is mounted").
- Where the code does it: `lib/features/startup/startup_preparing_screen.dart:23`
  `class StartupPreparingScreen extends StatelessWidget {` — a real screen class in the area.
- What a user would see: the neutral spinner surface on every launch; the inventory table that is
  supposed to list every screen omits it.
- Guard: none.
- Unsure: nothing.

### S7 · STALE-DOC · Calendar streak strip: doc says "current streak", code also shows "BEST RUN" and a fire emoji
- Where the doc says it: `docs/calendar_periods.md` "Monthly Stats Strip"
  ```
  the current streak (computed from up to 90 days of history, not just the displayed month)
  ```
- Where the code does it: `lib/features/calendar/calendar_screen.dart:712-719`
  ```
  label: isActiveStreak ? 'STREAK' : 'BEST RUN',
  value: completedSessions == 0
      ? '—'
      : (streakDays >= 3
            ? '🔥 ${streakDays}d'
            : (streakDays == 0 ? '0' : '${streakDays}d')),
  ```
- What a user would see: when the streak is broken the slot relabels to "BEST RUN" and shows the
  longest recent run; a 3+ day streak gains a 🔥. Neither behaviour is written anywhere.
- Guard: none found: searched `BEST RUN`/`isActiveStreak` in test/ — not checked.
- Unsure: where `isActiveStreak` is computed (calendar_state.dart not read for this).

### N1 · NO-RULE · Empty states are hand-rolled per screen with no shared widget or rule
- Where the code does it: `lib/features/calendar/day_session_list_screen.dart:389-403`
  ```
  class _EmptyState extends StatelessWidget {
    ...
    child: Text(
      isPast ? 'No sessions on this day.' : 'No sessions planned yet.',
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: OmniTheme.colors.textSecondary.withOpacity(0.6),
      ),
  ```
  and `lib/features/period/period_list_screen.dart:46-58` ('No training periods yet.', same
  bodyLarge/textSecondary-0.6 recipe). CalendarScreen has no empty-month text at all — it shows a
  `CircularProgressIndicator` while loading and an always-rendered grid otherwise
  (`calendar_screen.dart:141-146`). HomeScreen's only empty state is the NutritionSummaryCard's
  dash axes (documented in `widget_catalog/home_screen.md`).
- What a user would see: plain centred sentences in muted text on day list and period list; nothing
  on an empty calendar month; a structured dash state on the home nutrition card.
- Guard: none found: searched `_EmptyState`, 'No training periods yet' in test/ — not checked.

### N2 · NO-RULE · Unsaved-changes guards exist on two screens only; CreatePeriodScreen discards silently
- Where the code does it: guards exist in `lib/features/routine/routine_setup_screen.dart:144-151`
  (PopScope + `ConfirmationDialog.showUnsavedChanges`) and
  `lib/features/session/workout_session_edit_mode.dart:90-118`. `CreatePeriodScreen` has no
  PopScope and no guard: `lib/features/period/create_period_screen.dart` (searched
  `PopScope|WillPopScope|onPopInvoked` across `lib/features` — only routine and session files
  match); its back gesture discards a half-filled period form with no dialog.
- What a user would see: leaving a half-edited routine or session edit asks "Unsaved changes";
  leaving a half-created period throws the work away without asking.
- Guard: `test/` for the routine/session guards not checked; none found for the period screen.

### N3 · NO-RULE · One shared confirmation-dialog idiom, unwritten as a rule
- Where the code does it: every destructive confirm in this area goes through
  `ConfirmationDialog.twoChoice`/`showTwoChoice` with `isDestructive: true` and
  `barrierDismissible: true` — `home_screen.dart:686,761`,
  `day_session_list_screen.dart:233,370`, `period_list_screen.dart:112`. The shared widget is
  `lib/widgets/dialogs/confirmation_dialog.dart` (`showTwoChoice` :29, `showUnsavedChanges` :59,
  `twoChoice` :85). No doc states "all destructive confirms use ConfirmationDialog".
- What a user would see: the same dialog shape for every destructive action in the area.
- Guard: none found for the idiom as a rule (individual flows have key-pinned tests, e.g.
  `home-routine-open-confirm` keys — not checked).

### N4 · NO-RULE · Keyboard behaviour: no explicit dismissal anywhere; capitalisation varies by field
- Where the code does it: searched `unfocus|FocusScope|FocusManager|textInputAction` across
  `lib/features` — zero matches in this area's screens (only exercise_editor and add_food, outside
  the area, set `textInputAction`). Capitalisation: period name `TextCapitalization.words`
  (`create_period_screen.dart:157`), period notes `.sentences` (:262), profile name editor
  `.words` with `autofocus: true` (`profile_screen.dart:647-649`), measurements numeric keyboards
  (`profile_screen.dart:859,913,921,1303,1311,1321`). No select-on-focus anywhere in the area.
- What a user would see: keyboards stay up until the user dismisses them or a dialog closes;
  names auto-capitalise, numbers don't.
- Guard: none found.

### N5 · NO-RULE · Bottom primary action: shared OmniBottomCTA on three screens, inline full-width buttons on the rest
- Where the code does it: `OmniBottomCTA` anchors the primary action on
  `day_session_list_screen.dart:92-97` ('+ New Planned Session', null on past days),
  `period_list_screen.dart:75-78` ('+ New Period'), `create_period_screen.dart:89-91` ('Save').
  Home, onboarding and startup use full-width `FilledButton`/sheet instead (onboarding
  `onboarding_screen.dart:322-331`, startup failure `startup_failure_screen.dart:96-110`). No doc
  rule says when a screen gets a bottom CTA vs an inline button.
- What a user would see: form/list screens in the calendar-period flow keep one consistent bottom
  button; onboarding and startup failure put their single action inline.
- Guard: `day_session_list_screen.dart:87-89` cites
  `docs/plans/day-session-list-bottom-cta-plan.md` (plan doc, not a standing rule).

### N6 · NO-RULE · Locked/unavailable explanations: one written-out case (health permission), the rest silent
- Where the code does it: `lib/features/settings/settings_screen.dart:901-935`
  ```
  'Permission was denied. Allow access in your phone settings '
  'to turn this on.',
  ...
  onPressed: AppSettings.openAppSettings,
  child: const Text('Open settings'),
  ```
  By contrast, past-day read-only in the day list is silent (add/edit/delete callbacks are simply
  `null`, `day_session_list_screen.dart:139-143`; the empty state says nothing about why), and the
  Lean Mass read-only row shows just an em dash (`profile_screen.dart:296-299` carve-out comment).
- What a user would see: settings explains a denied permission and offers a jump to system
  settings; a past calendar day offers no explanation of why nothing can be added.
- Guard: none found.

### I1 · INCONSISTENT · Raw exception text in profile snackbars vs the no-developer-terminology principle
- Where the code does it: `lib/features/profile/profile_screen.dart:1013` and `:1099`
  ```
  ).showSnackBar(SnackBar(content: Text('Failed to save entry: $e')));
  ```
  The startup failure screen's own doc comment forbids developer terminology ("no 'console', no
  'log', no 'error', no raw exception text", `startup_failure_screen.dart:14-16`), and
  `navigation_and_screens.md` repeats it for the startup surface — but no rule extends that to
  other surfaces, and the profile log sheets print the raw exception.
- What a user would see: "Failed to save entry: Exception: ..." on a failed measurement save,
  while startup failures are carefully plain-language.
- Guard: none found.

### D1 · DOC-OFF-STANDARD · Visual values in app_philosophy §8
- Where the doc says it: `docs/app_philosophy.md` §8 — "collapsed (7%) and expanded (92%)" (percent
  values in a philosophy doc; `documentation_standard.md` forbids visual values; not re-read this
  run — the standard's rule is quoted in `common.md`).
- Where the code does it: S1 above.
- What a user would see: n/a (doc hygiene).
- Guard: none.

### D2 · DOC-OFF-STANDARD · theme_and_settings.md self-flags copied implementation content
- Where the doc says it: `docs/theme_and_settings.md` Theme System section
  ```
  > **Flagged, not owned here (documentation standard §5).** The `AppTheme` enum
  > block and the token-field table below are copied implementation content
  > (§3.5/§3.4). ... bringing them into conformance is a follow-up
  ```
- Where the code does it: `lib/core/constants/omni_theme.dart:4-10` — the enum matches the doc's
  copy exactly (6 values, verified).
- What a user would see: n/a (doc hygiene; the doc already admits it).
- Guard: none.

## NOTICED (defects seen in passing, one line each)
- NOTICED: `lib/features/calendar/calendar_screen.dart:483` — period highlight parses
  `colorHex` with `int.tryParse(hex, radix: 16)` and falls back to primary at 0.14 opacity; a
  malformed-but-7-char hex silently renders as the theme accent, not the chosen colour.
- NOTICED: `lib/features/home/home_screen.dart:131` — `_minSheetExtent = 0.0` means the collapsed
  sheet is fully off-screen; the drag handle is unreachable until the logo is tapped (by design per
  comments, but it means "collapsed" in the doc's sense does not exist).

---

## Pattern matrix

| Screen | P1 top bar | P2 section header | P3 empty state | P4 locked/unavailable | P5 confirm dialog | P6 unsaved guard | P7 text entry | P8 bottom action | P9 sheets/modals | P10 theme tokens | P11 a11y/overflow | P12 charts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| HomeScreen | AppBar + `HomeLogoButton` (toolbarHeight 60) | custom 'TRAIN' Text + 'HUB' eyebrow | NutritionSummaryCard dash axes (its own contract) | none | `ConfirmationDialog.twoChoice` 'Start New Session?' ×2 | none | none (no text entry) | none (hub sheet is the bottom surface) | `DraggableScrollableSheet` hub; `showModalBottomSheet` nutrition/stats primers | tokens; raw `Colors.black.withOpacity` shadows, `Color(0xFF9E9E9E)` in home_tiles.dart | `Semantics` on EnergyTile active state; tile-side shrink-to-fit math | none |
| CalendarScreen | `OmniBackHeader('Calendar')` + OutlinedButton '+' | `_MonthHeader`/`_WeekDayRow` custom | none (loading spinner; grid always renders) | none | none | none | none | none | none | tokens; raw `Color(0xFF000000|value).withOpacity(0.14)` period highlight, `Colors.grey` | `FittedBox` scaleDown in stats strip | none (dot grid, not a chart) |
| DaySessionListScreen | `OmniBackHeader` | `_SectionHeader` custom Text | `_EmptyState` 'No sessions on this day.' / 'No sessions planned yet.' | none (past read-only is silent) | `ConfirmationDialog.showTwoChoice` delete + start-new | none | `_PlannedSessionForm` bottom sheet (title/note TextFields; capitalisation not checked) | `OmniBottomCTA` '+ New Planned Session' (today/future only) | `_PlannedSessionForm` as modal bottom sheet | tokens + `feelingColor` effort ramp | ? (not checked) | none |
| PeriodListScreen | `OmniBackHeader('Periodization')` | none (plain rows) | 'No training periods yet.' centred Text | none | `ConfirmationDialog.twoChoice` 'Delete Period' | none | none | `OmniBottomCTA` '+ New Period' | none | tokens | ? (not checked) | none |
| CreatePeriodScreen | `OmniBackHeader('Create Period'/'Edit Period')` | custom small section labels | n/a (form) | none | none | none (back discards silently — N2) | TextField words (name, maxLength 50), sentences (notes), `showDatePicker` via `_DateField` | `OmniBottomCTA` 'Save' (disabled while saving) | `showDatePicker` | tokens + raw hex `_colorPalette` (10 Material hexes) | ? (not checked) | none |
| ProfileScreen | `OmniBackHeader('Profile')` | `OmniCardHeader` per measurement (uppercased) | em dash for missing values (`measurement_value`) | Lean Mass read-only row, em dash, no explanation | delete confirm lives in history sheet (not verified here — ?) | none | name dialog (words, autofocus); numeric keyboards; height cm/ftin branch | none (no bottom CTA) | `showModalBottomSheet` avatar options / log sheet / history sheet | tokens; raw computed `fontSize` (:190), `fontSize: 12` (:933) | `Semantics(button: 'Edit avatar')` | `MeasurementSparkline` + `ScrollableTrendChart` (history sheet) |
| SettingsScreen | `OmniBackHeader('Settings')` | `OmniCardHeader` eyebrows: PREFERENCES / SOUNDS & ALERTS / WORKOUT / HEALTH / APPEARANCE | n/a | `_HealthDeniedNotice` + 'Open settings' | `showDialog` 'Enable Timer Notifications?' | none (applies immediately, no save button) | none (segmented toggles + sheets only) | none | `_SoundPickerSheet` / `_IntervalPickerSheet` via `showModalBottomSheet` | tokens | ? (not checked) | none |
| OnboardingScreen | none (no app bar) | custom page content | n/a | none | none | none | none | full-width `FilledButton` 'Get Started' inside page body | none | tokens + raw `Color(0xFF060B14)` button foreground | `FittedBox` on CTA text | none |
| OmniSplashScreen | none | none | n/a | none | none | none | none | none (auto-`pushReplacementFade`) | none | raw `Colors.white.withOpacity(0.85)` on wordmark | ? (not checked) | none |
| StartupPreparingScreen | none | none | n/a | none | none | none | none | none | none | tokens (listens to `OmniTheme.activeThemeListenable`) | ? (not checked) | none |
| StartupFailureScreen | none | none | n/a | none | none | none | none | full-width `FilledButton` 'Retry' (disabled while retrying) | none | tokens | ? (not checked) | none |
| MaintenancePlaceholderScreen | plain `AppBar` with back IconButton | custom | n/a | n/a | none | none | none | none | none | tokens | ? | none |

Cells marked `?` were not checked this run (semantics labels, tap-target sizes and text-scale
overflow beyond the quotes above; the profile history-sheet delete dialog). Dead-code row
(MaintenancePlaceholderScreen) is quoted for completeness only — it is unreachable.
