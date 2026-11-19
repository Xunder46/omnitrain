# Plan 245 — The session summary lists each exercise with what was logged, in place of the month grid

Review item 4 (owner suggestion, accepted 2026-11-18: "add the per-exercise list, in place of the mini calendar").
Phone only. No wire, watch, model or storage change.

## Goal and acceptance

After this change the summary shows an `EXERCISES` card between the group cards and the `DISTANCE` / `SESSION NOTE` cards. One row per exercise that has logged work, in the session's order: the exercise name, and under it the logged work: each set as `reps×weight unit` (`10×60 kg`), each hold / interval / drill entry as its time (`10:00`), each round as its time. The month grid, the month-label header and the `N workout days / M rest days` line are removed. The `Open Calendar` button stays and works as today (post-workout: pushes a calendar; opened from the calendar: pops back).

Acceptance: S-24501..S-24510 (pure builder) and S-24511..S-24516 (screen) green; the ones marked "fails without" are red at the base commit; the existing summary tests that read the grid are rewritten as listed in Readers; `flutter analyze` at baseline (181 issues, 0 errors); `test/ui_standards_contract_test.dart` and `test/docs_indexing_contract_test.dart` green; full suite no new red; Docs delta applied.

## What the user sees

- After a workout, under the Strength / Cardio cards, an `EXERCISES` card: `Bench Press` then `10×60 kg · 8×60 kg · 6×62.5 kg`; `Plank` then `01:00 · 00:45`; `Rowing` rounds as times.
- A skipped set, an interval or round that never started, and an exercise with nothing logged are not listed. A session with nothing to list shows no `EXERCISES` card.
- Bodyweight sets read `12 reps`, or `12 reps +10 kg` with added weight. Weights follow the Weight unit setting.
- The month grid and the rest-day count are gone from the summary (the calendar is one tap away on `Open Calendar`).
- To SEE it: finish any workout with a few sets; or open a past session from the calendar.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-24501 | New pure function `buildSummaryExerciseRows(List<Map<String, dynamic>> exercisesWithEntries, {required String weightUnitLabel, required String Function(double kg) formatWeight})` in `lib/core/utils/summary_exercise_rows.dart`, returning `List<SummaryExerciseRow>` (`effortId`, `name`, `items`: `List<String>`). Input is `WorkoutState.getExercisesWithEntries()` (entry maps built by `SessionSummaryBuilder.buildExercisesWithEntries`, `session_summary_builder.dart:321`). It reads no state and no settings. | `session_summary_builder.dart:buildExercisesWithEntries` |
| D-24502 | Item text by `effortKind`: `set`: per entry not `skipped` and with `reps` > 0 (a set with no reps is nothing, S-24510): weight > 0 -> `<reps>×<formatWeight(weight)> <unit>`; else `extra-weight` > 0 -> `<reps> reps +<formatWeight(extra)> <unit>`; else `<reps> reps`. `timed` and `drill`: per entry with `elapsedSecs` > 0: `OmniDateUtils.formatTimerDigits(elapsedSecs)`. `round`: per entry with `actualDuration` > 0: `formatTimerDigits(actualDuration)`. Any other kind: no row. A row with no items is dropped. | `entry_rows.dart:SetRows.entry`, `session_summary_builder.dart:buildExercisesWithEntries`, `date_utils.dart:formatTimerDigits` |
| D-24503 | Why filter by value, not by state: Finish does not yet drop never-started intervals, holds and rounds (review item 27), so a stored `TimedInstance` / `RoundInstance` with 0 elapsed must not read as work. A set never logged is already not stored at Finish (docs/session_summary.md). | `session_core_io.dart:loadHistoricalSession`, `docs/session_summary.md` line 19 |
| D-24504 | Screen: `_buildExerciseSection()` (like `_buildDistanceSection`, `session_summary_screen.dart:1069`) returns `[SizedBox(height: 16), OmniCardHeader(title: 'EXERCISES'), OmniSurface(...)]` or `const []` when there are no rows. It is placed after `..._buildGroupCards(theme)` and before `..._buildDistanceSection()`. Each row: name (`titleSmall`/bold as the distance card names its rows), then the items in a `Wrap` separated by ` · `-less spacing (spacing 12): each item a `Text`. The unit comes from `UnitFormatter.weightLabel(widget.settingsState)` and the number from `UnitFormatter.formatWeightValue(kg, widget.settingsState)`. No new colour literal, no raw `Card` (UI standards). | `session_summary_screen.dart:1069`, `unit_formatter.dart:70` |
| D-24505 | Removed from the screen: `_buildCalendarHeader`, `_buildCalendarCard`, `_buildCalendarGrid`, `_loadCalendarData` and its call at `_loadAsyncData`, the fields `_workoutDays` and `_daysInMonth`, the getters `_viewMonth` and `_viewTodayDay`, `_monthName` if it is then unused. Kept: `_calendarState`, `_openCalendarScreen`, `_refreshOriginatingCalendar`, `openedFromCalendar`, `originatingCalendarState` (they gate discard, the note, the planned link and the Open Calendar behaviour). | scout sheet Q6 (`.work/crew/item4/scout-1.md`) |
| D-24506 | `Open Calendar` button: the existing `_buildOpenCalendarButton()` on its own row (centred) directly under the SESSION NOTE card, no header and no card; same text, same handler. Default taken by the lead (product detail the owner did not specify); recorded in `.work/review-feedback.md`. | owner suggestion + default |
| D-24507 | `OmniDateUtils.daysElapsedInMonth` (plan 239) is left in place: its own unit test `S-23901` still holds and another caller may exist; check with grep, and if the screen was its only caller leave it and say so in the evidence (not deleted here). | `summary_rest_days_elapsed_test.dart` |

## Scenarios

Fixtures. Level A (pure, `test/summary_exercise_rows_test.dart`): hand-built entry maps in the shape of `buildExercisesWithEntries` rows (`id`, `name`, `effortKind`, `entries`); `formatWeight = (kg) => kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toString()`, `weightUnitLabel = 'kg'` unless stated. Level B (screen, Mock harness only, `test/summary_exercise_list_screen_test.dart`): copy the harness and seeding helpers of `test/session_summary_distance_test.dart` (it already pumps the summary over a seeded session, post-workout and `openedFromCalendar: true`); surface 600x1200.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24501 | A: one `set` effort `Bench Press`, entries `{reps 10, weight 60.0, skipped false}`, `{8, 60.0}`, `{6, 62.5}`. | one row, items `['10×60 kg', '8×60 kg', '6×62.5 kg']`. | the function does not exist |
| S-24502 | A: set entries `{10, 60.0, skipped false}` and `{0, 0.0, skipped true}`. | items `['10×60 kg']`. | same; passes both ways once built (mutation: skipped check removed) |
| S-24503 | A: three set entries: `{12, weight 0.0, extra-weight 10.0}`, `{12, weight 0.0}`, `{12, weight 0.0, extra-weight 0.0}`. | items `['12 reps +10 kg', '12 reps', '12 reps']`. | same |
| S-24504 | A: `timed` entries `{elapsedSecs 600, timedState finished}`, `{elapsedSecs 0, timedState notStarted}`, `{elapsedSecs 45, timedState finished}`. | items `['10:00', '00:45']`. | same |
| S-24505 | A: `drill` entries `{elapsedSecs 3725, finished}`, `{0, notStarted}`. | items `['1:02:05']` (formatTimerDigits hours form). | same |
| S-24506 | A: `round` entries `{rounds 1, actualDuration 180}`, `{rounds 2, actualDuration 0}`, `{rounds 3, actualDuration 125}`. | items `['03:00', '02:05']`. | same |
| S-24507 | A: three efforts: all sets skipped; timed with only zero-elapsed entries; a set effort with `entries: []`. | empty list (no rows). | same |
| S-24508 | A: efforts in order `B` (set), `A` (timed), `C` with `effortKind 'mystery'` and one entry. | rows `[B, A]` in input order; `C` has no row. | same |
| S-24509 | A: `weightUnitLabel 'lbs'`, `formatWeight = (kg) => (kg * 2.2).toStringAsFixed(1)`, entry `{10, weight 60.0}`. | `['10×132.0 lbs']`; proves the unit label and the formatter are both used. | same |
| S-24510 | A: set entries `{reps 0, weight 60.0, skipped false}` and `{5, 60.0}`. | items `['5×60 kg']`. | same; passes both ways once built (mutation: the `reps > 0` check removed) |
| S-24511 | B: post-workout summary of a session with `Bench Press` (sets 10×60, 8×60 logged) and `Plank` (a finished 60 s hold). | `EXERCISES` header visible; texts `Bench Press`, `10×60 kg`, `8×60 kg`, `Plank`, `01:00` found; the header sits below the first card and above `SESSION NOTE` (compare `getTopLeft` y). | the card does not exist |
| S-24512 | B: the same session opened with `openedFromCalendar: true`. | same rows and order. | same |
| S-24513 | B: a session whose only exercise has no logged work. | no `EXERCISES` header; no crash. | passes both ways on purpose (mutation: header shown with no rows) |
| S-24514 | B: any session. | `find.textContaining('workout days')` finds nothing; no widget shows the month label text; `Open Calendar` is found once, below `SESSION NOTE`; with `openedFromCalendar: false` tapping it pushes a `CalendarScreen` (the existing S-003 assertion, kept in `calendar_summary_screen_bugs_test.dart`). | the grid, label and totals line exist today |
| S-24515 | B: a rolling session (`isRolling`) with one logged set exercise. | the list shows it. | same as S-24511 |
| S-24516 | B: Settings `preferredWeightUnit = 'lbs'`, a 60 kg set. | the row reads `10×132.3 lbs` (what `UnitFormatter.formatWeightValue(60, settings)` returns, computed in the test by the same call) and not `kg`. | the card does not exist |

## Input-reality checklist

1. Writers and units: sets are `EffortObservation` rows (reps `valueInt`, weight `valueReal` in kg) written by the logger and the watch importer; intervals are `TimedInstance.actualDurationSecs` (seconds) and rounds `RoundInstance.actualDurationSecs`. Weights are converted at read by `UnitFormatter` with the live Weight unit setting.
2. Lifecycle: never-started, skipped and zero-elapsed entries are filtered by value (D-24503); an exercise with no remaining item has no row (S-24507); rolling sessions list like any other (S-24515); a historical (calendar-opened) summary reads the same maps from the repository (S-24512); an edited session shows the edited values (the maps are rebuilt per build).
3. Settings: the Weight unit setting changes the numbers; the summary already reads settings at build and the Edit Session route returns to a rebuilt screen, so no live listener is added; `n/a` for a settings change while the summary sits in the back stack (it is rebuilt on return).
4. Time: `n/a`, no date logic remains on this screen after the grid is removed.
5. Cost: `getExercisesWithEntries()` is an in-memory pass over cached maps (no repository read); it runs once per build here and once more for DISTANCE. Accepted: tens of entries.
6. Words: old wording swept (grep in Docs delta). New wording on screen: `EXERCISES`, `reps`, units.
7. Slot competition: `n/a` (no sync path touched).

## Phases

1. **P1 builder-app**, scope `lib/core/utils/summary_exercise_rows.dart` (new), `test/summary_exercise_rows_test.dart` (new): the pure function and S-24501..S-24509. No full suite.
2. **P2 builder-app** (after P1), scope `lib/features/session/session_summary_screen.dart`: add `_buildExerciseSection`, wire it, remove the grid pieces (D-24504..D-24506), the `Open Calendar` row. Exact code in the brief. No full suite.
3. **P3 builder-app** (after P2), scope the Readers' test files and `test/summary_exercise_list_screen_test.dart` (new): S-24511..S-24516, and the listed rewrites. No full suite.
4. **P4 lead**: full suite once, `flutter analyze`, mutation pass, `crew-docs-keeper` (Docs delta), plan-lint after, reviewer.

## Readers

Tests that read the removed grid, label or totals (rewritten in P3 as listed): `test/calendar_summary_screen_bugs_test.dart` (S-001 month label: delete, the grid is gone; S-002, S-003, S-004 stay and must stay green), `test/header_standardization_test.dart` (`S-007 calendar card is OmniSurface...`, `S-008`, `Phase 2.2: date, note, and calendar headers are OmniCardHeader above their cards`, `Phase 2.2: modality chip lives in the first card's OmniCardHeader actions` count of headers), `test/screen_widget_test.dart` (`rolling session still shows group card, note, and calendar sections`, `session note appears before calendar section`), `test/session_finish_timers_test.dart` (`Session summary shows Open Calendar button`), `test/summary_rest_days_elapsed_test.dart` (S-23902 and S-23903 read the totals line: delete them and say so; S-23901 stays). Param-only readers that must stay green untouched: `entry_identity_summary_test`, `session_summary_distance_test`, `session_summary_effort_row_test`, `session_summary_planned_link_test`, `session_summary_inverted_window_test`, `summary_note_survives_quick_done_test`. P3's brief says: run each of these files after the edit.

## Mutation list (lead)

(a) skipped check removed (S-24502); (b) weight>0 test inverted or `extra-weight` branch removed (S-24503); (c) zero-elapsed filter removed (S-24504, S-24506); (d) round filter on `actualDuration` removed (S-24506); (e) rows with no items kept (S-24507); (f) unit label hard-coded `kg` (S-24509, S-24516); (g) section placed after the note (S-24511); (h) the empty-section guard removed (S-24513); (i) `Open Calendar` handler removed (S-24514 plus the S-002/S-003 tests).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/session_summary.md` | MODIFIED | focuses on session-level outcomes instead of per-exercise detail | shows each exercise with the work logged in it, under the session-level outcomes | S-24511 |
| `docs/session_summary.md` | MODIFIED | 5. Calendar card | 6. Open Calendar button | S-24514 |
| `docs/session_summary.md` | MODIFIED | 4. Session note | 5. Session note | S-24511 |
| `docs/session_summary.md` | ADDED | - | 4. Exercise list (the `EXERCISES` card) | S-24511 |
| `docs/session_summary.md` | MODIFIED | Month grid and Open Calendar navigation button | One row per exercise with logged work, then the Open Calendar button | S-24511 |
| `docs/session_summary.md` | REMOVED | - Per-exercise rows | - | S-24511 |
| `docs/session_summary.md` | MODIFIED | Calendar card renders today's month; "Open Calendar" pushes | "Open Calendar" pushes | S-24514 |
| `docs/session_summary.md` | MODIFIED | Calendar card renders the **session's month**; "Open Calendar" pops | "Open Calendar" pops | S-24514 |
| `docs/calendar_periods.md` | MODIFIED | 1. The embedded calendar card (the monthly grid + "workout days / rest | 1. The summary shows no calendar grid; | S-24514 |
| `docs/design_system.md` | MODIFIED | `SESSION NOTE` (note card), month label (with `Open Calendar` in actions) | `EXERCISES`, `SESSION NOTE` (note card) | S-24514 |
| `docs/navigation_and_screens.md` | MODIFIED | the embedded calendar card renders the **historical session's month** (not today), | the summary shows an exercise list and no calendar grid, | S-24514 |

The keeper adds a short `## Exercise list` section to `docs/session_summary.md` (rule D-24502, the filters, the unit rule) citing S-24501..S-24509 and S-24511..S-24516, and checks `docs/calendar_periods.md` lines 96-101 as a whole (the second numbered item about `Open Calendar` stays true). Stale-term sweep (done by the lead): `grep -rIn "calendar card\|per-exercise detail\|Per-exercise rows\|workout days /\|embedded calendar\|month grid\|monthly grid" docs` outside plans, history, releases returned `session_summary.md` 5, 13, 66, 71, 336, 337, `calendar_periods.md` 96, 98, `design_system.md` 183, `navigation_and_screens.md` 191 (the other `month grid` hits in `calendar_periods.md` 8 and 227 describe `CalendarScreen` and stay).

## Open items

1. (owner) The `Open Calendar` button now sits alone under the note, centred; say if it should live elsewhere.
2. (owner) A summary of a session with more than about 20 sets in one exercise wraps over several lines; nothing is cut.
3. Item 27 (Finish drops never-started intervals, holds and rounds) is not done; this list tolerates them by value (D-24503).

## Predicted files

`summary_exercise_rows.dart` (+70), `session_summary_screen.dart` (+60 −120), `summary_exercise_rows_test.dart` (~170), `summary_exercise_list_screen_test.dart` (~250), five existing test files (small), docs (~40 lines across five).

## Progress

- [x] Seeded
- [x] P1 pure builder (10 tests)
- [x] P2 screen
- [x] P3 tests (P3a five existing files flipped, P3b six screen tests)
- [x] P4 verify (13 summary files, 157 tests green), mutation pass (14 of 14 killed), docs (keeper), review (0 blocker, 1 major, 3 minor, all fixed by the lead)
- [ ] (owner) look at it on a device, Open items 1 and 2

## Assumption Log

- 2026-11-18: base commit in `.work/item4/base.txt` (f81d7d0a), branch `claude_develop`. Another session's uncommitted files (`test/food_catalog_load_test.dart`, `macos/Flutter/GeneratedPluginRegistrant.swift`) are not part of this plan and are never staged.
- 2026-11-18: ids S-245xx: none found in `test/`, `docs/`, `watch/` (grep run).
- 2026-11-18: scout sheet `.work/crew/item4/scout-1.md`; two quoted items spot-checked by the lead against the files (`_buildExercisesWithEntries` timed keys at `session_summary_builder.dart:371`, `formatTimerDigits` at `date_utils.dart:251`).

- 2026-11-18: no architect run: the lead wrote the seed with phases and plan-lint was clean before P1 (cost discipline, as plan 244).
- 2026-11-18: full suite on this Windows machine: +7029 passed, 1074 failed; the base commit f81d7d0a gives +7015 passed, 1075 failed; the sets of failing test names are identical except one base-only name (`food_library_own_copy_test` S-13317, flaky or order). The 1074 are Windows environment failures (path separators and CRLF in source-scanning tests, e.g. `ui_standards_contract_test` and `docs_indexing_contract_test`: 11 red at base and now). No new red. analyze 178 issues (baseline 181).
- 2026-11-18: review fixes by the lead (comments, one test name, one doc list item, one doc word), all in files this plan touched; re-ran the touched tests green.

## Feedback

(none yet)
