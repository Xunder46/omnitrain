# Session Summary — Feature Documentation

## Overview

The Session Summary screen appears after workout completion and shows each exercise with the work logged in it, under the session-level outcomes (plan 245, `test/summary_exercise_list_screen_test.dart` `S-24511 a post-workout style summary lists each exercise with its logged work`).

Current hierarchy:

1. Header
2. Session info card (Duration and Rest Time for standard sessions; the EFFORT row with its Calories pill for every session)
3. Context-aware modality group cards (Strength, Cardio, Sports, Isometric)
4. Exercise list (the `EXERCISES` card), then the `DISTANCE` card when an entry holds a distance
5. Session note
6. Open Calendar button

The screen keeps existing summary navigation actions (edit, save as routine, discard) and the bottom Done action.

A post-workout summary reports the finished session to its `onSessionSaved` hook (which links a planned session) once, when the screen opens — not on Done — so leaving with Back completes the plan too. A historical summary never calls it.

A set the user never logged is not stored at Finish, so it is never in this summary's sets, volume or bests, and a set exercise left with no logged set is removed at Finish, except in a session the watch had a part in, where the exercise stays with no sets (an exercise that never held a set stays, with zero sets; plan 157a, plan 218 (`test/finish_drops_unlogged_sets_test.dart` `S-15713`), `test/finish_drops_unlogged_sets_test.dart` `S-15708`, `test/finish_drops_unlogged_sets_screen_test.dart` `S-15709`).

The Finish confirmation before it counts only the exercises the user did (a lift with a logged set, or a started timed, drill or round exercise), not every exercise in the session (plan 217, `test/finish_completed_exercise_count_screen_test.dart` `S-21704`).

Finish on a workout with nothing done in it (no logged set, no started timed, drill or round exercise on the phone, and no set, timed, round or hold the watch has sent) asks `Discard Workout?` (`Nothing was logged, so this workout won't be saved.`) instead of saving an empty workout; Discard deletes it like the empty-workout case, Cancel keeps it open. `WorkoutState.finishWouldSaveNothing` decides, and decides after the wrist import passes already queued, so a wrist set still on its way counts; a workout the watch runs with nothing logged is discarded the same way (plans 220 and 228, `test/finish_nothing_logged_discards_test.dart`, `test/finish_nothing_logged_discards_screen_test.dart`, `test/finish_wrist_nothing_logged_discards_test.dart`).

### Effort Rating Capture

The **session effort rating** is how hard the whole session was: 1 is the easiest, 5 the hardest. It is stored in `TrainingSession.sessionFeeling` — the field name is historical; it is not a feeling score. Ratings recorded before the redefinition (when the prompt asked how the session felt) are read as effort ratings on the same scale with no conversion: an owner decision (Stats redesign D-5, `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md`).

**Structure.** One sheet widget, `EffortRatingSheet` in `lib/widgets/session/effort_rating_sheet.dart`, serves both of this screen's entry points: the **automatic post-workout prompt** (`_showFeelingSheet`) and the **EFFORT row's add/change control** (`_openEffortRatingSheet`) in the first summary card, which exists on post-workout and calendar-opened summaries whether or not the prompt is enabled. Both write through `WorkoutState.updateSessionFeeling` (the sheet's `onRated`), and the summary rebuilds when the sheet closes. The same sheet asks after the phone's own Finish of a watch session; that path is [Watch Session Capture](watch_session_capture.md)'s. Rating colors come only from `feelingColor` / `effortTileTextColor` in `lib/core/utils/session_feeling_utils.dart`, which read `OmniThemeColors.intensityRamp` (see [Design System](design_system.md)).

**Rules.**

- **The automatic prompt must be answered.** It has no close or skip control and cannot be dismissed without a choice; the Effort Rating setting (`SettingsState.showFeelingSurvey`, see [Theme & Settings](theme_and_settings.md)) is the only way not to be asked. It appears only on a post-workout summary of an unrated session, at most once. This is the phone's rule: the wrist's own question can be skipped, which records nothing, so the phone's prompt still appears (see [Watch Session Capture](watch_session_capture.md)).
- **The automatic prompt is first-answer-wins.** A rating the watch settles while the prompt is open closes it and shows in the EFFORT row, and the prompt's own answer is written only while the session has none, so the watch's number is never overwritten by it. The EFFORT row's Add/Change control stays an explicit edit and still overwrites. Verified by `test/rating_first_answer_summary_test.dart` (group `Summary automatic effort question, first answer wins (plan 42a)`: `S-4303 the watch rating closes the automatic question and stays stored`, `S-4303 the user's own answer closes the sheet once`, `S-4303 a late tap on the open question cannot overwrite the watch's answer`) and by `test/rating_first_answer_state_test.dart` (`S-4304 onlyIfUnrated leaves the stored rating alone, the default still writes`).
- **The user-opened sheet is optional.** The user chose to open it, so closing it without a choice leaves the rating unchanged.
- **A change reaches the calendar.** On a calendar-opened summary a saved rating refreshes the originating `CalendarState` — the same path Discard uses — so the day list shows the new tint on return.
- **The rating is never drawn as ramp-colored text.** The lower ramp steps sit below the text-contrast floor, so the EFFORT value uses the stat pills' shared value color and the intensity is carried by a non-text marker in the rating's ramp step (D-15 in `docs/plans/2026-09-24-01-stats-pr1-effort-rating-plan.md`).
- **Rolling sessions can still be rated.** They have no session clock, so their info card drops Duration and Rest Time but keeps the EFFORT row.
- **The EFFORT row explains itself.** Under the value a muted caption reads `How hard the session felt`, and the pen button with the tooltip — an outlined rounded-square icon-only `OmniUtilityIconButton` on the same line as the value, right after it rather than at the column's far edge — reads `Change rating` once a rating exists, and `Add rating` before one (key `omni_session_effort_rating_button`, icon `Icons.edit_outlined` when rated and `Icons.add` before one). The same test also checks the outline, the tap size and that the pen sits right after the value. Verified by `test/session_summary_calories_test.dart` (group `S-13411 an unrated session`: `the pen reads Add rating with a plus icon`; group `S-13402/S-13411 a rated session with an estimated energy row`: `the pen is icon-only and the Calories pill sits to its right`) and by `test/session_summary_effort_row_test.dart` (group `S-3211 the EFFORT pill carries its own caption`: `S-3211 a rated session shows the caption under the value`, `S-3211 an unrated session shows it too`, `S-3211 a rolling session shows it too`; group `S-3212 the button names what it does`: `S-3212 an unrated session reads Add rating, then Change rating after the sheet rates it`, `S-3212 a rated session reads Change rating, and tapping it opens the sheet on the stored rating`).
- **A watch session in history is rated like any other.** An imported watch session is an ordinary `TrainingSession`, so its summary shows the rating the wrist recorded, or offers to add one, through the same control. Verified by `test/watch_session_summary_integration_test.dart` (`S-285`, `S-286`).
- **The phone's rating is final.** A rating written here is never replaced by one the wrist sends later: the import applies a wrist rating only while the session has none (D-138 of `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`). Verified by `test/watch_session_import_test.dart` (`S-264`).
- **Both devices ask the same question.** The sheet's question, scale and end labels are the ones `watch/contract/watch_effort_rating_contract.json` gives the wrist. Verified by `test/watch_effort_rating_copy_parity_test.dart` (`S-287`).
- **A finished session's rating is sent to Fitness.** With Write workouts on, a rating saved for a finished session, here or by a wrist import, is also sent as its Fitness workout's Workout Effort (1 to 5 becomes 2 to 10); the iPhone does this on iOS 18 and later only, and leaves a value the owner set in Fitness alone. Verified by `test/health_effort_test.dart` (`S-90-1`, `S-90-5`).

Verified by:

- `test/screen_widget_test.dart` (group `SessionSummaryScreen`): `feeling modal is non-dismissible and blocks summary controls`, `selecting tile 3 dismisses the feeling modal and persists`, `does not show feeling modal when session feeling already exists`.
- `test/interaction_flow_test.dart`: `does not show feeling survey sheet when disabled in settings`.
- `test/session_summary_effort_row_test.dart`: the prompt's copy and refresh (`Task 1a`); add, change, pre-selection and the selected tile's text color (`S-3`, `Fresh session — Change replaces …`, `Change sheet pre-selects …`); closing without a choice by tap and by swipe (`S-5.5`, `Change sheet swiped down …`); calendar-opened summaries — no prompt, add/change, day-list refresh (`S-4/S-5`, `S-5: day list → …`); value color and marker (`EFFORT value is drawn …`); pre-redefinition answers (`S-6`); the sheet's date subtitle (`Sheet subtitle …`); rolling sessions (`Task 3`).
- `test/rating_first_answer_state_test.dart`: the wrist's settled answer reported once and adopted by the live session (`S-4301`), the phone's stored rating kept with no callback (`S-4302`), the late automatic answer writes nothing while the default still writes (`S-4304`).
- `test/rating_first_answer_summary_test.dart` (group `Summary automatic effort question, first answer wins (plan 42a)`): the watch answer closes the open prompt and shows in the row, the user's own answer closes it once, a late tap cannot overwrite (`S-4303`).
- `test/header_standardization_test.dart`: `S-008: rolling session shows combined card with EFFORT row only (Duration/Rest hidden)`.

---

## Screen Layout

The screen renders a CustomScrollView over OmniGradientBackground with this order:

| Section | Content |
|---------|---------|
| Header | Session title only (the app bar shows no date or modality badge) |
| Session info card | Duration and Rest Time, then the heart-rate row when the session has one ([Heart rate](#heart-rate)), then the EFFORT row with its Calories pill (rolling sessions: no Duration / Rest Time row — see [Effort Rating Capture](#effort-rating-capture)); the formatted start date/time and the modality chip sit in this card's header |
| Group Cards | One card per group that has data in this session |
| Exercise list | One row per exercise with logged work, then the Open Calendar button |
| Session Note | Inline TextField with debounce save (a note still pending when Done or Back is pressed is written first) |

What is not rendered in the active layout:

- Session RPE card
- Standalone PR card

## Exercise list

Between the group cards and the distance section the screen renders an
`EXERCISES` card (key `omni_session_exercise_card`): one row per exercise that
has logged work, in the session's order, each row carrying the exercise's name
and then one short text per logged item. The rows come from
`buildSummaryExerciseRows` in `lib/core/utils/summary_exercise_rows.dart` over
`WorkoutState.getExercisesWithEntries()`; the function reads no state and no
settings, so the post-workout and calendar-opened summaries build the same
rows (`test/summary_exercise_list_screen_test.dart`: `S-24511 a post-workout
style summary lists each exercise with its logged work`,
`S-24512 a calendar-opened summary lists the same rows in the same order`,
`S-24515 a rolling session lists its logged exercise`). The card sits below
the first card and above `SESSION NOTE` (S-24511), and a rolling session lists
its logged work like any other (S-24515).

- **A set reads its reps and weight.** A logged set reads `reps×weight unit`
  (`10×60 kg`), with the Weight unit setting's label and `UnitFormatter`'s
  converted value both applied, so the rows follow the Weight unit setting.
  Verified by `test/summary_exercise_rows_test.dart` (group `Summary exercise
  rows (plan 245)`: `S-24501 sets read reps x weight`, `S-24509 the unit label
  and the formatter are both used`) and by
  `test/summary_exercise_list_screen_test.dart` (`S-24516 weights follow the
  Weight unit setting`).
- **A bodyweight set reads its reps**, `12 reps`, or `12 reps +10 kg` when it
  carries added weight. Verified by `test/summary_exercise_rows_test.dart`
  (group `Summary exercise rows (plan 245)`: `S-24503 bodyweight sets read
  reps, with added weight when given`).
- **A timed, drill or round entry reads its time.** A hold or drill reads its
  elapsed time in `OmniDateUtils.formatTimerDigits` form (`10:00`, hours form
  `1:02:05`); a round reads its actual duration. Verified by
  `test/summary_exercise_rows_test.dart` (group `Summary exercise rows (plan
  245)`: `S-24504 timed entries read their elapsed time, zero gives nothing`,
  `S-24505 drill entries read their elapsed time in hours form`,
  `S-24506 rounds read their actual duration, zero gives nothing`).
- **Nothing logged gives nothing.** A skipped set, a set with no reps, a timed
  or round entry that never started or recorded no time, and an effort kind
  other than `set`, `timed`, `drill` and `round` give no item; an exercise
  with no item left gives no row, and the rows keep the input order. Verified
  by `test/summary_exercise_rows_test.dart` (group `Summary exercise rows
  (plan 245)`: `S-24502 a skipped set gives no item`,
  `S-24510 a set with no reps gives no item`,
  `S-24507 an exercise with no logged work gives no row`,
  `S-24508 rows keep input order and unknown kinds give no row`).
- **A session with nothing logged shows no card.** The section is omitted
  rather than rendering an empty card. Verified by
  `test/summary_exercise_list_screen_test.dart` (`S-24513 a session with no
  logged work shows no EXERCISES card`).
- **The month grid is gone from this screen.** The summary no longer renders
  a month grid, a month-label header or the `N workout days / M rest days`
  totals line. The `Open Calendar` button stays, on its own row under the
  SESSION NOTE card, and keeps its behaviour: a post-workout summary pushes a
  fresh `CalendarScreen`, a summary opened from the calendar pops back.
  Verified by `test/summary_exercise_list_screen_test.dart` (`S-24514 the
  month grid and the rest-day line are gone, Open Calendar stays`) and by
  `test/calendar_summary_screen_bugs_test.dart` (group `S-002 — Open Calendar
  pops back on historical summary`, and the test whose comment says S-003:
  `tapping "Open Calendar" with openedFromCalendar=false (default) pushes a
  new CalendarScreen on top`).

### Heart rate

The info card carries a heart-rate row — two stat pills side by side, the
session's average and maximum heart rate — between the Duration / Rest Time
row and the EFFORT row. It is shown only when the session has a session-scope
`SensorSummary` carrying average and maximum heart rate, which the watch
importer stores from the session end (see
[Watch Session Capture](watch_session_capture.md)); the model requires the two
values together, so there is no average-only case. Without one the card is
unchanged, and a rolling session — which has no Duration / Rest Time row —
shows the heart-rate row too. The screen loads it in `_loadAsyncData` next to
the rest time; that load runs only while `workoutState.currentSession` is
non-null, so a past session opened from the calendar does not show the row.
Verified by `test/session_summary_heart_rate_test.dart` (group
`SessionSummaryScreen heart-rate row (S-9654..S-9657)`: `S-9654 seeded: the
card shows avg and max side by side`, `S-9654 not seeded: the card is
unchanged, no row`, `S-9656 a rolling session shows the heart-rate row too`,
`S-9657 the row sits between Duration and Effort`).

Notes:

- Group cards are conditional by data presence; empty groups are hidden.

### Calories

The EFFORT row is two halves side by side: the rating pill on the left with the
outlined pen edit button right beside the rating value, and the Calories pill
(`omni_session_calories_pill`, label CALORIES) on the right. The pill shows on
every session, rolling ones included.

- **An estimate is marked with a tilde, a measured value is not.** An estimated
  row reads `~32 kcal`; a row the watch measured reads `250 kcal` with no
  estimate mark; and with nothing stored the pill reads `—`. Verified by
  `test/session_summary_calories_test.dart` (group `S-13402/S-13411 a rated
  session with an estimated energy row`: `the pen is icon-only and the Calories
  pill sits to its right`; group `S-13407 a measured energy row`: `reads plain
  kilocalories, no estimate mark`; group `S-13412 every session shows the
  Calories pill`: `a session with no energy row reads an em dash`).
- **The watch sends its measured energy.** A session the watch ran or followed
  carries the wrist workout's active-energy total on its end, and the pill reads
  that number plain, no tilde; a session with no watch, or with Health refused,
  stays on the `~` estimate (see
  [Watch Session Capture](watch_session_capture.md)). Verified by
  `watch/watchos/Tests/WatchSessionEngineTests/WatchActiveEnergyTests.swift`
  (`testS13473AWristEndedSessionCarriesItsEnergyTotalAndValidates`,
  `testS13475AFollowedSessionCarriesBothItsMarkAndItsEnergyTotal`).
- **Every session carries the pill.** A rolling session — which has no
  Duration / Rest Time row — shows the Calories pill too, and a measured row
  the watch writes later lands on an already-open summary through
  `noteWristSummary`. Verified by `test/session_summary_calories_test.dart`
  (group `S-13412 every session shows the Calories pill`: `a rolling session
  shows the pill and no Duration/Rest row`, `a late measured row lands through
  noteWristSummary`).
- **Where the number comes from.** `ActiveEnergyService.settle(sessionId)`
  stores the estimate when a session ends and again when its duration is
  edited; ending a session never fails on it — every failure is caught (see
  [State Management & Services](state_management/services_and_utils.md),
  `ActiveEnergyService`).
- **The formula is active energy = (MET − 1) × body weight in kg × hours**, with
  the MET per section in `kActiveEnergyMets`
  (`lib/core/constants/active_energy.dart`): resistance 3.5, cardio 6.0,
  isometric 3.0, sports 6.0. A session with one of the four modality ids uses
  its whole duration at that section's MET; Free Training, an unknown modality
  id or a rolling session uses the per-section time split the Mix view already
  computes (`StatsProgressService.sessionTimeBySectionFor`). A Free Training
  session with timed work and no set shares its whole length across the timed
  sections (plan 179). Verified by
  `test/active_energy_service_test.dart` (groups `Mock —
  ActiveEnergyService.settle` and `Hive — ActiveEnergyService.settle`:
  `S-13401 resistance 3600 s at 80 kg stores 200.0`,
  `S-13403 cardio 1800 s at 80 kg stores 240.0`,
  `S-13402 isometric 1102 s at 80 kg stores 31.8355… unrounded`,
  `S-13403 sports 5400 s at 70 kg stores 525.0`,
  `S-13404 Free Training 3600 s with measured cardio and isometric`,
  `S-13414 an unknown modality id takes the Free Training branch`,
  `S-13416 Free Training with only set work: resistance remainder`,
  `S-13409 a finished rolling session with measured isometric seconds`,
  `S-13409 a rolling session counts its measured seconds even when it carries
  a modality id`, `S-13409 a finished rolling session with nothing measured
  writes no row`, `S-13409 an unfinished session writes no row`,
  `S-13409 a session with a modality and no duration writes no row`).
- **The weight is the latest `bodyweight` measurement on file, in kilograms and
  above zero.** With no usable weight the app stores nothing and the pill reads
  `—`; a latest weight of zero or less writes no row too. An estimate stores
  the weight it used and a later settle reuses it, so logging a new weight
  never rewrites an old session, and a duration edit recomputes at that stored
  weight. Verified by `test/active_energy_service_test.dart` (same groups:
  `S-13405 no weight, then a lbs weight, then a kg weight`,
  `S-13415 a latest weight of 0 kg writes no row`,
  `S-13415 a latest weight of −5 kg writes no row`,
  `S-13406 a re-estimate reuses the stored weight; an edit recomputes`) and by
  `test/active_energy_lifecycle_test.dart` (`S-13406: a duration edit
  recomputes an estimated row at its stored weight`).
- **A measured row is never overwritten by an estimate.** A row the watch
  writes survives both a settle at end and a settle at a duration edit.
  Verified by `test/active_energy_service_test.dart` (same groups:
  `S-13407 a measured row survives a settle untouched`) and by
  `test/active_energy_lifecycle_test.dart` (`S-13407: a measured row survives
  an end and a duration edit`).
- **The read-out rounds once, here.**
  `SessionSummaryService.getSessionEnergy(sessionId)` returns
  `({int kcal, bool measured})?` — kilocalories rounded to whole numbers, the
  one rounding on the figure — and null when nothing is stored. Verified by
  `test/active_energy_service_test.dart` (same groups: `read-out: estimated
  31.8355 reads (32, not measured)`, `read-out: a measured 250.4 row reads
  (250, measured)`, `read-out: no row reads null`).

---

## Group Cards

Cards are shown in fixed order when data exists:

1. Strength
2. Cardio
3. Sports
4. Isometric

Each card contains:

- Group title
- Comparison delta chip from GroupDelta, against the last like session
- Two metrics
- Inline PR rows for that group (if any)

Per-group metrics:

- Strength: Sets and Total Volume
- Cardio: Rounds and Total Time
- Sports: Rounds and Total Time
- Isometric: Holds and Total Time

Behavior details:

- Cardio rounds are counted from timed entries.
- Sports time comes from completed round durations.
- Strength volume is formatted using preferred weight unit (kg or lbs).
- A set marked skipped was not done: it is not counted in Sets, and its planned weight and reps feed no volume, best weight or e1RM (plan 227, `test/skipped_set_counts_for_nothing_test.dart`).
- Saving an edited workout (Edit Session, Save Changes) finishes the rounds that were running or paused at their planned length, but a round that was never started stays never started: the summary's round count and time do not grow (plan 232, `test/edit_save_keeps_unstarted_rounds_test.dart`).

---

## Comparison basis

The per-group figures compare with the last finished session that is like this one, not with the last session of any kind (plan 246, `test/summary_comparison_basis_test.dart`, group `Summary comparison basis (plan 246)`):

- A session started from a routine compares with the last finished session of the same routine (`S-24601 routine current compares with the same routine, not a free session`).
- Any other session compares with the last finished session of the same type: one with no routine and the same modality, and a session with no modality (Free Training) matches only other sessions with no routine and no modality (`S-24604 free null-modality current compares with the last free null-modality session, not a routine session`, `S-24605 type match excludes other modalities and routine sessions`).
- Unfinished sessions and sessions started after the current one are skipped (`S-24607 unfinished and started-after-current sessions are skipped`).
- A group the like session does not have gets no figure — `—` where other sessions show a delta — while a group it has gets its delta (`S-24606 a group the like session lacks gets no figure, a group it has gets the delta`).
- With no like session at all — only a free session before a routine one (`S-24602 routine current with only a free session before it has no figure and no basis`), or only a different routine (`S-24603 routine current with only a different routine before it has no figure and no basis`) — every figure is hidden and there is no basis.

One muted line above the group cards names the basis when a like session exists and at least one figure is shown (key `summary_comparison_basis`):

- A routine session reads `Compared with your last <routine title> (<date>)`, and a free session reads `Compared with your last <type name> session (<date>)` (`S-24611 a routine summary says it compares with the last run of that routine`, `S-24613 a free session says it compares with the last session of its type`).
- The routine's label is the current session's title, or `this routine` when that title is blank or missing (`S-24608 blank title falls back to this routine`, `S-24608 null title falls back to this routine`); the type's label is the modality's display name, as in the label checks of the two type tests above.
- No like session (`S-24612 no like session means no line`) or no figure shown, such as a like session with no effort (`S-24614 a like session with no group shows no line`) means no line.

---

## Distance

The Summary is the one phone surface where a person types or corrects a
distance: the live screen and Edit Session have no distance field, so a
distance the phone should hold is entered here, on the post-workout summary or
on a past session's. Which entry a row belongs to is
[Entry Identity](data_models.md#entry-identity)'s rule (D-324) and what a
stored distance means is [Distance Source & Pairing](distance_source.md); this
section is what the Summary does with it.

**Structure.** `SessionDistanceCard` in
`lib/widgets/session/session_distance_card.dart` renders rows the screen builds
in `_buildDistanceRows`; the card reads no state and the screen owns every
rule. The rows come from the session's efforts in the order
`getExercisesWithEntries()` gives them, then in entry order, built from
`WorkoutState.getEffortDistanceEntries` — the same list every distance write
addresses (D-328), so the row a tap names is the entry the write reaches.
Tapping a row opens `showMetricEditPopup` with the `distance` metric type, and
the answer goes through `WorkoutState.setEntryDistance` or
`confirmEntryDistance`.

**Rules.**

- **An entry is listed when it was tracked through Cardio.** The picker's
  modality decides the effort kind at the moment an exercise is added, and only
  Cardio yields `timed`, so the effort kind is the stored record of Cardio
  tracking — the modality itself is never stored. That holds in every kind of
  session: a Cardio session, a routine, Free Training, a rolling session, a
  watch-started session. Anything tracked through another modality is not
  listed.
- **A Cardio-tracked entry keeps its row even with no distance**, reading as
  absence rather than zero, because the field has to exist somewhere to be
  filled in.
- **The section is hidden when it has no rows**, as the group cards are.
- **A row carries a name, a distance and a unit, and nothing else.** No pace,
  total, change indicator or duration is added anywhere on the Summary: the
  values belong to Stats. The outlined pencil button that ends each row marks it
  editable and opens the same editor as the row; it is not data.
- **The card says how to edit a row.** A hint above the rows reads
  `Tap a row to enter or correct it.`, and each row ends with an outlined pencil button
  (`OmniUtilityIconButton`); a row with no distance keeps its em dash. Verified by
  `test/session_summary_distance_test.dart` (`S-3213 the card says how to edit
  a row, above the rows`, `S-3213 a session with no distance rows shows neither
  the card nor the hint`, `S-3214 every row ends with an outlined pencil
  button, and the row still opens the editor`, `S-3215 the card fits 280 dp with a 60-character
  name`).
- **Confirming the pre-filled value keeps the stored metres**, which is what
  confirms an estimate; any other value is stored as entered, and zero removes
  the distance. The field's label never carries the estimate marker, because
  pressing Ok makes the value an entered one.
- **A correction reaches Stats** through the stored value, since a
  `StatsProgressService` is built per Stats load rather than held.
- **Unit and precision** are `UnitFormatter`'s: metres are stored, the display
  unit is the preference's, and no km↔mi constant appears on this screen.

Verified by:

- `test/session_summary_distance_test.dart`: the section's rows and their
  order, in km and in miles (`S-811`, `S-812`); correcting an estimate (`S-813`),
  confirming one unchanged (`S-814`), entering zero (`S-815`), cancelling by
  an outside tap and by cleared text (`S-816`), filling an empty entry
  (`S-817`); which sessions list what — Free Training (`S-818a`), a resistance
  session with no section (`S-818b`), a watch-imported session (`S-818c`), a
  distance row stored on a non-timed effort shows nothing (`S-1303`); the
  post-workout summary's write on Done (`S-820`); an Edit
  Session discard (`S-821`); a routine (`S-822`); a plank tracked through
  Cardio (`S-823`).
- `test/crown_control_tap_to_edit_test.dart`: the dialog's parse, clamp and
  rounding for the `distance` type, and its title.
- `test/entry_identity_summary_test.dart`: the rows the section lists after a
  delete (`S-855`), the entry that holds a value typed after an add (`S-856`),
  and a row that belongs to no entry (`S-858`).

---

## Rest Time and Duration

Rolling sessions have no session clock, so neither value is shown for them
(`test/header_standardization_test.dart`, `S-008`).

Rest Time is aggregated from EntryRest records by:

- collecting closed rest intervals across all efforts in the session
- clipping each interval to the session wall-clock window (`startedAtMs` to
  `max(startedAtMs, endedAtMs)`: an end stored before the start leaves an empty
  window, so every interval clips to zero length and contributes no rest —
  `test/session_summary_inverted_window_test.dart`, `S-153: an inverted session
  window contributes no rest and the summary still renders`)
- merging overlapping or adjacent intervals so concurrent rests are not
  double-counted
- summing merged positive durations

Formatting:

- Human-readable duration for positive values
- 0 when no closed rests exist

---

## Technical Architecture

### Screen: SessionSummaryScreen

File: lib/features/session/session_summary_screen.dart

Inputs:

- WorkoutState
- RoutineState
- SessionSummaryService
- SettingsState, TimerAlertService, RestNotificationService
- optional onSessionSaved callback
- optional `openedFromCalendar: bool` (default `false`)
- optional `originatingCalendarState: CalendarState` (refreshed after
  Discard or a rating change when `openedFromCalendar == true`)

Two entry points feed this screen:

| Entry | `openedFromCalendar` | Behaviour |
|-------|----------------------|-----------|
| `WorkoutSessionScreen` finish → `pushReplacement` (post-workout) | `false` (default) | "Open Calendar" pushes a fresh `CalendarScreen`; "Done" ends + clears + `popUntil(isFirst)`; "Discard" deletes + `popUntil(isFirst)`. |
| `CalendarScreen` past-day tap with a single completed entry, or `DaySessionListScreen` completed-row tap (historical) | `true` | "Open Calendar" pops back like the system back button; "Done" just clears in-memory state and pops back; "Discard" permanently deletes the historical session and pops back to the originating calendar or day list (the originating `CalendarState.refresh()` is awaited so the deleted indicator disappears from the grid). |

Summary data loaded on entry:

1. computeSessionSummary from WorkoutState
2. buildTemplateDraftExercises from WorkoutState
3. compareGroupsToPreviousSession from SessionSummaryService
4. computePRs from SessionSummaryService
5. groupPrsByEffortKind from SessionSummaryService
6. buildGroupMetrics from SessionSummaryService
7. computeSessionRestTimeMs from SessionSummaryService — rests clip to the
   session's window, and an end stored before the start contributes no rest
   (`test/session_summary_inverted_window_test.dart`, `S-153`)
8. getPreferredWeightUnit from SessionSummaryService

Effort rating sheet: see [Effort Rating Capture](#effort-rating-capture).

### Service: SessionSummaryService

File: lib/core/services/session_summary_service.dart

Key public methods:

- compareGroupsToPreviousSession
- computePRs — records PRs using the **Epley e1RM** formula (`StatsProgressService.epley1RM = weight × (1 + min(reps, 12) / 30)`), the same definition the in-workout toast uses. The screen passes its own session id so the just-finished workout's PRs are not compared against themselves. See `docs/plans/summary-pr-parity-plan.md`.

  The returned list is collapsed to at most one `PRAchievement` per
  exercise — when the same exercise appears in more than one block
  (e.g. a user clones a block several times), the input list carries
  one `ExerciseSummary` per block and the method groups by `exerciseId`
  before emitting. The verdict ("is this a PR") is unchanged; only
  the entry count collapses. Set count, total volume, and the
  per-exercise breakdown are byte-equal before and after this step.
  See `docs/plans/stats-summary-fix-pack-plan.md` PR 1.

  A parallel **reps-axis** pass emits bodyweight PRs
  (`metricLabel: 'reps'`) using `StatsProgressService.getAllTimeBestReps`
  — the same source-of-truth query the in-session reps-PR toast uses.
  The two passes cannot collide because an
  exercise on the e1RM axis never has a non-null `bestReps` and vice
  versa. See `docs/plans/stats-summary-fix-pack-plan.md`
  Item 2 (rep-based record parity).
- saveRoutineFromDraft
- computeSessionRestTimeMs — sums closed `EntryRest` intervals after clipping
  each to the session's window and merging overlaps once; a session whose stored
  end precedes its start has an empty window and the total is `0`
  (`test/session_summary_inverted_window_test.dart`, `S-153`)
- getSessionHeartRate — returns the session's average and maximum heart rate
  as `({int avgBpm, int maxBpm})?` from the first session-scope
  `SensorSummary` that carries both values, rounded to whole bpm; null when
  there is none — an effort-scope summary does not count. Verified by
  `test/session_summary_heart_rate_test.dart` (group
  `SessionSummaryService.getSessionHeartRate (S-9651..S-9653)`: `S-9651 avg
  127.6 / max 171.2 rounds to (128, 171)`, `S-9652 no summaries, or only a
  non-session scope, answers null`).
- buildGroupMetrics
- groupPrsByEffortKind
- getPreferredWeightUnit

Repository compatibility:

- Uses WorkoutRepository interface only

Tests: `test/session_summary_heart_rate_test.dart` — `S-9651` rounding to
whole bpm, `S-9652` null with no session-scope summary, `S-9654` the row and
its texts, absent without data, `S-9656` a rolling session, `S-9657` row order
Duration → heart rate → Effort.

---

## Models

File: lib/core/models/session_summary.dart

Key classes:

- SessionSummary
- SessionGroupMetrics
- ExerciseSummary
- PRAchievement
- GroupDelta
- SessionTemplateDraft
- SessionTemplateExercise
- TemplateTargetDraft

Important SessionSummary fields used by the current UI:

- totalDurationMs
- totalSets
- totalVolume
- totalRounds
- totalRoundDurationMs
- totalCardioDurationMs
- totalDrillDurationMs
- exercises

---

## Save as Routine

Available from the summary's overflow menu. The draft is editable — name, exercise order,
additions and removals — before it is persisted through `saveRoutineFromDraft`.

Each target's value comes from the entry's own row, read through `EntryRows` — never from the row a
store happens to return first. A `timed` or `drill` template carries no distance target, and its
extra-weight target is the first entry's own row. Verified by `S-1311`–`S-1315` in
`test/state_test.dart` and `S-1317` in `test/session_summary_distance_test.dart`.

---

## Code References

| Concern | File |
|---------|------|
| Summary screen | lib/features/session/session_summary_screen.dart |
| Summary service | lib/core/services/session_summary_service.dart |
| Summary models | lib/core/models/session_summary.dart |
| Summary computation in state | lib/state/workout/workout_state.dart |
| Repository interface | lib/data/repositories/workout_repository.dart |

---

## Related Documentation

- modality_based_exercise_ui.md
- my_routines.md
- app_philosophy.md
- data_models.md

---

Document Version: 1.3
Last Updated: April 13, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-10-13. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
