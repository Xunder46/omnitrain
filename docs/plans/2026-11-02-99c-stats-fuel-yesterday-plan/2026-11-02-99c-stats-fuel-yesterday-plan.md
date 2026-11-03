# 99c — Fuel reports the last 7 finished days, with honest colours

Series: `docs/plans/2026-11-02-99-stats-four-week-view-series.md` (owner decisions O-3, O-4, O-5). Builds on 99a/99b (uncommitted, other files).
Status: SEEDED by the lead 2026-11-02. Phone only. Another session owns the watch/timer files and has uncommitted edits in `lib/data/repositories/*_workout_repository.dart` and `lib/state/calendar/calendar_state.dart`: never touch them.

## Goal and acceptance

What a user sees on the Stats Fuel row:
1. The averages cover the 7 days ending **yesterday**; today is left out (Home shows it). The comparison range is the 7 days before that. The Training / Rest split uses the same 7 days, so it no longer flips during the day.
2. With fewer than 3 logged days in those 7, the four figures, their comparisons and the Training / Rest lines are replaced by one sentence, **"Log food on 3 days to see a weekly average"**. The "N/7 days logged" line stays.
3. Comparison arrows are neutral for every figure (target or previous week). Red only for **protein below its target**.
4. The row still opens the nutrition trend; it still appears only when the last 14 days hold logged food (today counts for that).

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-17201 | Window `[today − 7, today − 1]`, previous `[today − 14, today − 8]`, calendar arithmetic (`DateTime(y, m, d - n)`), via the existing `kFuelWindowDays = 7` | `stats_progress_service.dart` `computeFuelSummary` (~L2012-2079) |
| D-17202 | The series is read with `computeNutritionTrend(days: 2 * kFuelWindowDays + 1)` (today plus 14 days). Visibility keeps `kFuelVisibilityDays = 14`: the summary is null unless some point has `date >= today − (kFuelVisibilityDays − 1)` (today included) | same |
| D-17203 | `_trainingDayKeys(windowStart, yesterday)`: split over the same 7 days | same |
| D-17204 | New `const int kFuelMinLoggedDays = 3` in `lib/core/models/fuel_summary.dart` and `bool get showsAverages => loggedDays >= kFuelMinLoggedDays` on `FuelSummary`. The model still carries the averages; the widget decides what to draw | `fuel_summary.dart` |
| D-17205 | `FuelSection`: when `!summary.showsAverages` draw the sentence (key `fuel_not_enough_days`) instead of the two metric rows and the two split captions; `fuel_logged_days` always draws | `fuel_section.dart:94-230` |
| D-17206 | Comparison colour: `kFuelAbsent` stays `textMuted`; a protein comparison against a SET target that reads below it is `theme.colorScheme.error.withValues(alpha: 0.8)`; every other comparison is `themeColors.textSecondary` | `fuel_section.dart:299` |
| D-17207 | No "Today so far" line (O-3) | none |

Readers of `FuelSummary` / `computeFuelSummary`: `stats_screen.dart` (~L124, L339), `fuel_section.dart`, `test/fuel_row_screen_test.dart`, `test/nutrition_trend_screen_test.dart`; docs `stats_screen.md`, `nutrition.md`, `widget_catalog.md`, `data_models.md`. Constructors of `FuelSummary` in tests need no new argument (the new member is a getter).

## Scenarios (days are "days ago"; fixtures from the real clock like `fuel_row_screen_test.dart`)

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-17201 | Food: d0 4000 kcal, d1 1000, d7 3000, d8 5000 | `loggedDays` 2; `caloriesAverage` 2000; `previousCaloriesAverage` 5000 | old window included today (avg 2500) and put d7 in the previous range (4000) |
| S-17202 | Food on d1, d2, d3 vs only d1, d2 | `showsAverages` true vs false | getter absent |
| S-17203 | Completed session today and food d0 4000, d1 1000 | `trainingCaloriesAverage` null; `restCaloriesAverage` 1000 | today was a training day (4000) |
| S-17204 | Food only today | summary non-null, `loggedDays` 0, `caloriesAverage` null; food only on d14: summary null; only on d13: non-null with `previousCaloriesAverage` equal to that day | visibility and window bounds |
| S-17205 | Widget, summary with `loggedDays` 2: sentence text exactly `Log food on 3 days to see a weekly average`; `fuel_logged_days` reads `2/7 days logged`; keys `fuel_calories`, `fuel_protein`, `fuel_carbs`, `fuel_fat`, `fuel_split_training`, `fuel_split_rest` find nothing. Twin with `loggedDays` 3: sentence absent, keys present | as stated | no sentence existed |
| S-17206 | Widget, hand-built summary: protein average 100, target 150 (`↓ -50 g`); calories average 1800, target 2000 (`↓ -200 kcal`); carbs average 300, target 250 (`↑ +50 g`); fat average 50, no target, previous 60 (`↓ -10 g`) | `fuel_protein_change` colour is the error colour at alpha 0.8; calories, carbs and fat change colours equal `themeColors.textSecondary`; protein 200 vs target 150 is `textSecondary`; protein with no target and a lower previous is `textSecondary` | old rule coloured ↑ primary and ↓ error |

## Phases

| Phase | Agent | Write scope | Items | Order |
|---|---|---|---|---|
| P1 | crew-builder-app | `lib/core/services/stats_progress_service.dart`, `lib/core/models/fuel_summary.dart`, new `test/fuel_summary_window_test.dart` | D-17201..D-17204, S-17201..S-17204 | first |
| P2 | crew-builder-app | `lib/features/stats/widgets/fuel_section.dart` | D-17205, D-17206 (exact code in the brief) | after P1 |
| P3 | crew-builder-app | new `test/fuel_section_widget_test.dart` | S-17205, S-17206 | after P2 |
| P4 | crew-builder-app x2 | the files the red run names (`test/fuel_row_screen_test.dart`, `test/nutrition_trend_screen_test.dart`, others) | fixture dates and the removed today-in-window premise | after P3 |
| P5 | crew-docs-keeper | `docs/stats_screen.md` Fuel row, `docs/nutrition.md`, `docs/widget_catalog.md`, `docs/data_models.md` | the new window, sentence, colours | after P4 |

Done: touched tests green; lint not above 181; full suite shows no new failures against the known list; lead mutations (window end, previous start, split range, visibility bound, the 3-day threshold, the protein-under-target colour, the neutral colour); review, one fix round at most.

## Progress
- [x] P1 — `test/fuel_summary_window_test.dart` +8 (per lead; the file read this run holds 5 tests over both harnesses: S-17201, its twin, S-17202, S-17203, S-17204)
- [x] P2 — `fuel_section.dart` draws the sentence (`fuel_not_enough_days`) and the colour rule (D-17205, D-17206), read this run
- [x] P3 — `test/fuel_section_widget_test.dart` +6 (read this run: S-17205 ×2, S-17206 ×4)
- [x] P4 — `test/fuel_row_screen_test.dart` adapted (groups S-1102, S-1105–S-1107, S-1111, S-14041, S-14043, S-1259/S-1260/S-1261 incl. `a row with fewer than three logged days`), read this run
- [x] P5 — docs updated: `stats_screen.md`, `nutrition.md`, `widget_catalog.md`, `data_models.md` (this run; no test run — the lead runs the docs contract test)
- [ ] prove  - [ ] review
