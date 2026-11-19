# Review: 208-fuel-burned-per-day · Phases 1–3 · d5b4dc18b522777b52967be43a840d0a9ed4feea..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 2 · tests: 8110 passed, 4 skipped, 1 failed (watch_timer_push_test S-6323, other session's uncommitted timer work — governor run); the 11 Fuel/Health files in scope: 235 passed; `flutter analyze` 181 issues = baseline
Diff vs Predicted Files: conforms — `git-diff --stat <base> -- <paths>` shows exactly the 29 predicted paths (12 production, 8 tests, 9 docs); nothing outside. `test/stats_gallery_render_test.dart` shows whole-file as untracked; its FuelSummary call uses the new fields (`trainingLoggedDays`/`restLoggedDays`, no protein averages). `test/fuel_burned_summary_test.dart` is untouched, as S-20806 requires.

## Findings
1. [Minor] docs/nutrition.md:645 (and the summary row at :759) — "Burned per day averages Apple Health active energy" is iOS-only wording: on Android the same figure comes from Health Connect (D-16/D-18, tested by S-20827's Android half in `test/health_active_energy_read_test.dart`). An Android reader is told the figure comes from Apple Health. Fix: "averages the platform health store's active energy over the days with data" (the sentence before it already uses that wording). Guard: none (doc-only).
2. [Minor] docs/stats_screen.md:115 — "when recent food exists or a burn figure has one": "has one" has no referent (a burn figure does not "have" a figure). Fix: "…or a burn figure exists". The behaviour it describes is right and tested (S-20842, S-20848). Guard: none (doc-only).

Notes, not findings:
- Residue sweep clean: `trainingProteinAverage|restProteinAverage|fuel_split_training|fuel_split_rest|Training days: |Rest days: |g protein` over `lib`, `test`, `docs` (excluding `docs/plans`) finds no rendered or doc use. The only test-side hits are absence guards (`test/fuel_row_screen_test.dart:505-506`, asserting the retired keys render nothing) and fixture comments describing protein grams — intended.
- `lib/main.dart:26` imports `hive_workout_repository` — pre-existing root composition, outside the guarded dirs (`lib/state`, `lib/features`, `lib/widgets`, `lib/core`); `package:health/` appears only in `lib/core/services/health_platform_gateway_io.dart:25`. Both project checks hold.
- UI standards: no raw `Card`/`SnackBar`, no unkeyed new control, no colour literal in the diff; `fuel_section.dart` keeps `OmniSurface`/`OmniCardHeader`/`_caption` and the existing `InkWell`+`Semantics` pair (dropped in burn-only mode, as D-19 wants). No allowlist entry added, no ratchet raised.

## Assumption Log rulings
The plan's Assumption Log section is empty — no entries to rule on.

## Scenario coverage
- S-20801 → `test/fuel_row_screen_test.dart` group `S-20801` › `the split covers every logged day exactly once, and a running session is not a training day`; also `test/fuel_section_widget_test.dart` `S-20801 the split is one calories-only line and the burned line reads the window average`
- S-20802 → `test/fuel_row_screen_test.dart` group `S-20802/S-20803` › `S-20802 every logged day is a training day` › `draws no split at all`; widget twin in `fuel_section_widget_test.dart`
- S-20803 → same two files, `S-20803 no training day at all` / `S-20803 a card with no training day draws no split`
- S-20804 → `test/fuel_row_screen_test.dart` group `S-20804` (both boundary cases); `test/fuel_section_widget_test.dart` `S-20804 the split needs two logged days on each side`
- S-20805 → `test/fuel_section_widget_test.dart` `S-20805 with only 2 logged days the burn line still draws`
- S-20806 → regression guard: `test/fuel_burned_summary_test.dart` untouched and green (S-13430..S-13433)
- S-20820 → `test/health_active_energy_read_test.dart` `S-20820 — activeEnergyTotalsByDay sums per local day and skips non-numeric points`
- S-20821 → same file `S-20821 — activeEnergyDayBounds spans a DST day…` (governor: `TZ=America/New_York` run passes unskipped)
- S-20822, S-20825, S-20838 → superseded by owner 2026-11-17; not built, as the plan says
- S-20823 → `test/health_active_energy_read_test.dart` `S-20823 — Mock/Hive: the active-energy switch lifecycle…`
- S-20824 → same file, two tests: `S-20824 — … a refused switch (denied) reads nothing` and `S-20824 — … readDailyActiveEnergy only when the switch is on and a source exists`
- S-20826 → same file `S-20826 — the iOS Info.plist permission sentence…`
- S-20827 → same file `S-20827 — the per-day read calls the day query once per local day…`
- S-20828 → same file `S-20828 — web and desktop are inert…`
- S-20829 → `test/health_active_energy_settings_screen_test.dart` (five `testWidgets`: iOS, Android, macOS, switch lifecycle, body weight unchanged)
- S-20830 → `test/fuel_burned_per_day_test.dart` `S-20830 seven days of active energy average to the mean` (Mock and Hive)
- S-20831, S-20832, S-20833 → same file, one test each
- S-20834 → same file `S-20834 the reader gets exactly d7..d1 and is called once`
- S-20835 → same file, two tests: DST window and `ordinary date: 7 local midnights, oldest first`
- S-20836 → `test/fuel_burned_per_day_test.dart` `S-20836 the burn line is independent of the food-days gate`; widget twin in `fuel_section_widget_test.dart`
- S-20837 → `test/fuel_burned_per_day_test.dart`, two tests: throwing reader; never-completing reader with a 50 ms timeout
- S-20839 → `test/fuel_section_widget_test.dart` `S-20839 the caption lines read in the D-7 order and wording` (position-asserted) and `S-20839 Burned per day is absent when there is no figure`
- S-20840 → `test/fuel_burned_per_day_screen_test.dart` group `S-20840 wiring` (switch on: line + exactly one read; switch off: no read and the card equals the no-source card, full text list asserted)
- S-20841 → service half in `fuel_burned_per_day_test.dart`; widget halves in `fuel_section_widget_test.dart` (burn-only content, not tappable, still tappable with food, intake suppressed); screen half (tap pushes no route) in `fuel_burned_per_day_screen_test.dart` group `S-20841`
- S-20842 → service half `S-20842 no food and no counted burn day: nothing to show` ((a) two days below the floor, (b) empty reader); screen group `S-20842 nothing to show hides the card` (switch off, 2 days below floor)
- S-20843 → `test/fuel_burned_per_day_test.dart` `S-20843 food alone…`; widget twin `S-20843 with recent food and no burn figure…`
- S-20844 → `test/fuel_burned_per_day_test.dart` `S-20844 burn-only mode can carry both burn lines`; widget twin with order assertion
- S-20845 → `test/fuel_burned_per_day_test.dart` `S-20845 food on d13 counts as recent, d14 does not`
- S-20846 → `test/health_active_energy_read_test.dart` `S-20846 — the Android manifest declares…`
- S-20848 → service (`S-20848 health burn alone makes a burn-only summary`), widget (per-day-only and per-session-only burn-only cards), screen (`S-20848 no food, Health only`)
- Extra scenarios added during the build (not in the plan table): S-20833b (an infinite day is no data) and S-20833c (a key outside the day list is ignored) in `test/fuel_burned_per_day_test.dart`; S-20849 (the empty state keeps no Fuel card) in `test/fuel_burned_per_day_screen_test.dart`; S-20850 (runStartup hands the gateway to the switch; a gateway without the interface resolves denied) in `test/health_active_energy_startup_wiring_test.dart`; S-20851 (a summary built without `hasRecentFood` is the normal tappable card) in `test/fuel_section_widget_test.dart`
- No MISSING scenario.

## Questions
1. **Visibility (D-19/D-20)** — sound. `computeFuelSummary` returns `null` only when `!hasRecentFood && burned.average == null && burnedPerDay == null` (`lib/core/services/stats_progress_service.dart:2281-2282`); `StatsScreen` renders the card exactly on `_fuelSummary != null` (`lib/features/stats/stats_screen.dart:446`). Traces: no food + only session burn → S-20841 service test (summary non-null, burn-only); no food + only Health burn → S-20848; no food + neither → S-20842 (a) and (b), `null` on both harnesses; food at d13 shows `0/7 days logged`, d14 → `null` (S-20845). Burn-only rendering with no figure: `FuelSection` draws the per-session line only when `!_burnOnly || burnedKcalAverage != null`, so no dash appears — widget-asserted (S-20848 widget tests) and screen-asserted (`_textsUnder(_fuelSection)` contains no `—`). No input found where the card shows with nothing to show, or is absent while a burn figure or recent food exists.
2. **Failure containment (D-11/D-18)** — sound. The gateway catches every per-day query error and never throws (`lib/core/services/health_platform_gateway_io.dart`, `readDailyActiveEnergy`); a store missing entirely returns `{}` (S-20827's third fake). `computeFuelSummary` wraps the read in `try/catch` and `.timeout(kFuelActiveEnergyTimeout)` (5 s, `stats_progress_service.dart:224`), so a slow or throwing source only hides the line — S-20837 asserts every other field equals the same fixture's no-reader summary. A second Stats load while the first read is pending is guarded by `_loadGeneration` (`stats_screen.dart:97, 229, 249`): the stale load's result is dropped before `setState`. The orphaned post-timeout read completes into a discarded future; nothing is persisted, so no stale value can survive.
3. **Wiring and gating (D-9/D-12/D-17)** — sound. `createHealthPlatformService` constructs the plugin gateway only on iOS/Android (`health_platform_gateway_io.dart:32-37`); web/desktop get `UnavailableHealthPlatformService`, which implements `HealthActiveEnergySource` returning `{}`/`false` (S-20828 asserts the macOS host factory). `main.dart` passes the gateway as `activeEnergySource` only when it `is HealthActiveEnergySource` (`lib/main.dart:315-319`), guarded by S-20850's two startup tests. The Settings row's gate `!kIsWeb && (iOS || android)` (`lib/features/settings/settings_screen.dart`) matches that reality exactly and is asserted on all three platforms (S-20829); `denied` goes through the same `_resolveHealthToggle` path and shows the same `_HealthDeniedNotice` as the body-weight switch (S-20823, S-20824, S-20829's refusal test).
4. **Day arithmetic (D-6/D-14)** — sound. `activeEnergyDayBounds` and `fuelWindowDayStarts` both use calendar arithmetic (`DateTime(y, m, d ± k)`), so both stay on local midnight across a DST change; the gateway keys its sums by `bounds.start.millisecondsSinceEpoch`, which for a midnight input is the same instant `averageActiveEnergy` looks up. S-20821 (gateway bounds, 82,800/90,000 s) and S-20835 (window starts) both run under `TZ=America/New_York` and pass unskipped; S-20834 pins the exact `dayStarts` list the reader receives and S-20833c that keys outside it cannot reach the average.
5. **Docs** — every behaviour sentence in the nine docs names a test that exists in the tree (checked by reading the code/tests for the names: S-20801..S-20848, S-17204/S-17205, S-13430..S-13434, `records_nutrition_entry_test.dart`), and no live doc still describes the retired protein split, the retired keys `fuel_split_training`/`fuel_split_rest`, or "hidden when no food in 14 days" (residue grep above; hits only under `docs/plans`). The two Minor wording defects are in the Findings.

## Docs delta
- `docs/stats_screen.md` dash-marker → `kFuelMinSplitDays` wording -> applied
- `docs/stats_screen.md` `showsAverages` block → outside the food-days gate -> applied
- `docs/stats_screen.md` two split lines → split line; logged-days line and both burn lines always draw -> applied
- `docs/stats_screen.md` **Burned per day.** -> applied
- `docs/data_models.md` rest split → `trainingLoggedDays` -> applied
- `docs/data_models.md` `burnedPerDayAverage` -> applied
- `docs/nutrition.md` `readDailyActiveEnergy` -> applied
- `docs/nutrition.md` Burned per day averages Apple Health active energy over the days with data -> applied (marker matches; the sentence's Android wording is Finding 1)
- `docs/theme_and_settings.md` Read active energy -> applied
- `docs/state_management/services_and_utils.md` `HealthActiveEnergySource` -> applied
- `docs/stats_screen.md` `[Fuel row](#fuel-row) when recent food exists` → or a burn figure -> applied (marker matches; the garbled "has one" is Finding 2)
- `docs/stats_screen.md` **Burn-only card.** -> applied
- `docs/nutrition.md` entries (hidden once food has not been logged) → stops opening the trend -> applied
- `docs/nutrition.md` summary `null` unless some logged → nothing to show -> applied
- `docs/records_and_trends.md` Fuel row hides once food… → stops opening the trend -> applied
- `docs/theme_and_settings.md` Health Connect -> applied
- `docs/navigation_and_screens.md` `SettingsState(...)` ctor line → `activeEnergySource` -> applied
- Doc edits the table does not name, all applied: `docs/stats_screen.md` constants-table row for `kFuelVisibilityDays` and the two file-table rows (`fuel_section.dart`, `fuel_summary.dart`); `docs/widget_catalog.md` FuelSection row; `docs/state_management/app_state.md` `SettingsState` Depends-on line, `healthReadActiveEnergy` getter row and the two method rows; `docs/navigation_and_screens.md` `SettingsScreen` row's platform-health toggle list.
