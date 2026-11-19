# Plan 208 — Fuel card: calories-only split, a "Burned per day" line from Apple Health / Health Connect, and a burn-only card

> Status: Iteration 1 active, amended 2026-11-17 by owner answers A (both platforms) and B (card visibility): D-16..D-20, S-20827..S-20848. Q1 moot, Q2–Q4 defaults stand; Q5–Q6 new, defaults in force.
> Next handoff: owner device checks (see below), then the owner commits. Built and verified 2026-11-18.
> Binding conventions: `docs/global_conventions.md`, `docs/design_system.md` ("Shared pieces and rules per job"), `docs/documentation_standard.md`, `.github/copilot/pr-scope-budget.md`
> Track: phone app only (`lib/`, `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`). No watch, no sync contract, no schema/seed change.

## Goal and acceptance

The Stats screen's Fuel card averages intake over the 7 finished days ending yesterday. Its bottom lines today read
`7/7 days logged` · `Training days: 2022 kcal · 127 g protein` · `Rest days: —` · `Burned per session: 89 kcal · 9 sessions`.
After this PR:

- The training/rest split is one calories-only line, `Training days 2022 · Rest days 1850 kcal`, drawn only when both sides have enough logged days; otherwise it is absent (never a dash).
- A new line `Burned per day: 520 kcal · active, all movement` shows the 7-day average of Apple Health's daily **active** energy (walking plus workouts, not resting energy), over the days Health has data for; read from Apple Health on iPhone and Health Connect on Android; hidden below 3 such days, when access is off, when Health Connect is missing, and on web/desktop. The Android path is unit-tested on the host but **not seen on a device** (the owner cannot run Android).
- `Burned per session` is unchanged.
- Both burn lines show even when fewer than 3 days of food are logged.
- The card hides only when it has nothing to show (D-19). With no food in the last 14 days but a burn figure, it shows `Last 7 days` and only the burn lines that have a figure, and tapping it does nothing.
- No eaten-minus-burned "balance" line.

Owner decisions (2026-11-15, relayed by the governor) are recorded as D-1..D-7; the 2026-11-17 answers as D-16..D-20. Nothing has shipped, so there is no user data or migration to handle.

## Decision Ledger

Immutable. Change by superseding (`D-n supersedes D-m`). "Derived" entries are the planner's reading of an owner answer and stand unless the owner vetoes.

| ID | Decision | Source |
|---|---|---|
| D-1 | **Split wording.** One caption, key `fuel_split`, text exactly `Training days {T} · Rest days {R} kcal`, `{T}`/`{R}` = `trainingCaloriesAverage` / `restCaloriesAverage` rounded with the card's existing `_whole` (`double.round()`, no thousands separator, same as the `Calories` figure above it). No protein anywhere in the split. The keys `fuel_split_training` and `fuel_split_rest` are retired. *Derived:* the owner's example wrote `2,022`; the card prints `2022` everywhere else, so no separator. | owner 1, 2 |
| D-2 | **Split gate.** The split draws only when `showsAverages` (≥ `kFuelMinLoggedDays` = 3 logged food days) **and** `trainingLoggedDays >= kFuelMinSplitDays` **and** `restLoggedDays >= kFuelMinSplitDays`, with `kFuelMinSplitDays = 2` declared beside `kFuelMinLoggedDays` in `lib/core/models/fuel_summary.dart`. Otherwise no split widget exists at all (no dash line). | owner 2 + Q2 default |
| D-3 | **Model.** `FuelSummary` drops `trainingProteinAverage` and `restProteinAverage` and gains `int trainingLoggedDays`, `int restLoggedDays` (sizes of the two partitions `computeFuelSummary` already builds). The training-day rule is unchanged: a window day on which a **completed** session started; a running session does not count. | owner 1; residue rule |
| D-4 | **Burn lines are independent of the food gate.** `Burned per day` and `Burned per session` draw whether or not `showsAverages` holds. The card's own visibility is unchanged: `computeFuelSummary` still returns `null` (no card) when no food was logged in the last `kFuelVisibilityDays` (14) days, even if Health has data. *Derived (card visibility), vetoable.* | Q1 default |
| D-5 | **Burned per session unchanged:** same computation (`_burnedInWindow`), text, `~`, count, singular, and its dash `Burned per session: —` when no window session carries an energy row. | owner 3 |
| D-6 | **Burned per day rule.** Window days = the same 7 local calendar days d7..d1 (midnights by calendar arithmetic `DateTime(y, m, d - k)`, today d0 excluded). Each day's value = Apple Health's active-energy total for `[that midnight, next midnight)` as Health's own statistics sum (HealthKit merges overlapping iPhone + Watch samples, so no double counting). A day **counts** when its value is finite and `> 0`; missing, `0`, negative, NaN or infinite = no data (*derived: 0 = no data, vetoable*). Average = sum of counted values / number of counted days. Shown only when counted days `>= kFuelMinActiveEnergyDays = 3` (declared beside `kFuelMinLoggedDays`). Values keyed to any day outside d7..d1 are ignored. Not compared with any target or previous week. | owner 4 + accepted defaults |
| D-7 | **Burned per day wording and order.** Key `fuel_burned_day`, text exactly `Burned per day: {N} kcal · active, all movement`, `{N}` via `_whole`; no `~`, no day count. Caption order at the bottom of the card: `{n}/7 days logged`, split (D-2), `Burned per day`, `Burned per session`. No balance line anywhere. | owner 5, 6 + Q4 default |
| D-8 | **Platforms.** Only Apple Health on iOS is read. Android, web and desktop yield no data, so the line is hidden and nothing else on the card changes. | accepted default |
| D-9 | **Permission (Q3 default, existing pattern).** A new switch `Read active energy` in Settings ▸ HEALTH, under `Read body weight`, **iOS only** (`!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS`), off by default, key `healthReadActiveEnergyToggleKey = Key('health-read-active-energy-toggle')`, subtitle exactly `Shows the calories you burn per day, from all movement, on the Stats Fuel card. Only active energy is read.` Switching it on asks Health once for **read** access to active energy; the result persists under preference `health.readActiveEnergy` as `HealthToggleState` (`on` / `denied` / `off`), and `denied` shows the existing `_HealthDeniedNotice`. Stats never prompts. iOS does not tell apps whether read access was refused, so a refusal normally reads as "on, no data" and the line simply stays hidden. | Q3 default; `settings_screen.dart:880` pattern |
| D-10 | **Info.plist.** Append to `NSHealthShareUsageDescription` in `ios/Runner/Info.plist`, after the existing text and one space, exactly: `It also reads your active energy so the Stats screen can show the calories you burn per day.` The existing text is unchanged. | owner 4 |
| D-11 | **Freshness.** Health is read fresh on every Stats load: 7 day queries, nothing cached or persisted, no `WorkoutRepository`, schema or seed change. The read is only made when the D-9 switch is `on`. A read that throws or takes longer than `kFuelActiveEnergyTimeout = Duration(seconds: 5)` yields no data: the line hides, the rest of the card and screen load normally. | design |
| D-12 | *(Code design, stated.)* New plugin-free interface `HealthActiveEnergySource` in `lib/core/services/health_platform_service.dart` with `Future<bool> requestActiveEnergyReadPermission()` and `Future<Map<int, double>> readDailyActiveEnergy(List<DateTime> dayStarts)` (key = day-start epoch ms). It is **not** added to `HealthPlatformService`, so the 8 test fakes that implement that interface stay untouched. `HealthPluginPlatformService` and `UnavailableHealthPlatformService` implement both. `SettingsState` gains an optional named ctor param `HealthActiveEnergySource? activeEnergySource`; `lib/main.dart` passes the same gateway object when it implements the interface. | design |
| D-13 | *(Code design, stated.)* `StatsProgressService.computeFuelSummary` gains an optional named param `Future<Map<int, double>> Function(List<DateTime> dayStarts)? readDailyActiveEnergy` (null = no Health line) and a pure `static List<DateTime> fuelWindowDayStarts(DateTime today)` returning d7..d1 oldest first; the average is a pure `static double? averageActiveEnergy(Map<int, double> byDay, List<DateTime> dayStarts)`. `StatsScreen._loadData` passes `widget.settingsState.readDailyActiveEnergy`. `SettingsState.readDailyActiveEnergy(dayStarts)` returns `{}` without calling the source unless the switch is `on` and a source exists. | design |
| D-14 | *(Code design, stated.)* The io gateway reads one statistics query per day: `getHealthIntervalDataFromTypes(startDate: start, endDate: end, types: [ACTIVE_ENERGY_BURNED], interval: end.difference(start).inSeconds)` where `end = DateTime(y, m, d + 1)` (23 h / 25 h on DST days). Day bounds and bucketing are pure top-level functions in `health_platform_gateway_io.dart` (`activeEnergyDayBounds`, `activeEnergyTotalsByDay`), tested on the host like `pluginActivityTypeFor`; a point belongs to the day containing its `dateFrom` (`start <= dateFrom < end`), points of one day are summed, non-numeric points skipped. A day whose query throws is left out; the others stand. Off iOS the method returns `{}` and permission returns `false` without touching the plugin. | design |
| D-15 | **Shared tree.** The working tree carries other sessions' uncommitted work (including `lib/core/services/stats_progress_service.dart` outside the Fuel region and the untracked `test/stats_gallery_render_test.dart`). Every edit here is additive and local to the symbols named; never revert, reformat or re-order other changes; run the formatter only on the exact files you changed, by path. No git commands. | AGENTS.md |
| D-16 | **Platforms (supersedes D-8).** Apple Health on iOS and Health Connect on Android are both read; web and desktop yield no data. Android needs `<uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED" />` beside `READ_WEIGHT` in `android/app/src/main/AndroidManifest.xml`, and the comment above the Health block names it. The permission-rationale route (the `<queries>` intent and the `ViewPermissionUsageActivity` alias) already covers every Health permission, so nothing else is added. Health Connect missing, not installed or failing yields no data: the line hides. The Android path is host-tested only and unverified on a device. | owner A |
| D-17 | **Switch (supersedes D-9).** Everything in D-9 holds, except that the `Read active energy` row shows on iOS **and** Android (`!kIsWeb` and `defaultTargetPlatform` is `iOS` or `android`) and is absent on web and desktop. The subtitle is D-9's text unchanged (it names no platform). On Android, Health Connect reports a refusal, so the `denied` notice can appear there. | owner A |
| D-18 | **Gateway read (supersedes D-14).** Same per-day query on both platforms: `getHealthIntervalDataFromTypes(startDate: start, endDate: end, types: [ACTIVE_ENERGY_BURNED], interval: end.difference(start).inSeconds)`, with D-14's day bounds and bucketing. On Android this runs Health Connect's `aggregateGroupByDuration`, which merges overlapping data origins by the user's app-priority list; that is the dedupe we rely on, as HealthKit's statistics sum is on iOS. Health Connect returns a bucket of `0` for a day with no records, which D-6's "0 = no data" rule drops. The plugin call sits behind a constructor seam on `HealthPluginPlatformService` (`dayQuery`, default = the plugin call), so both platforms' reads are tested on the host with a fake. A day whose query throws is left out; a read that throws before any day (Health Connect unavailable) returns `{}`. Off iOS and Android, `{}` and `false` without touching the plugin. | owner A |
| D-19 | **Card visibility (supersedes D-4; changes D-5 in burn-only mode).** "Recent food" = food logged in the last `kFuelVisibilityDays` (14) days, today included: today's rule, unchanged, so 13 days ago counts and 14 does not (see Q5). The card shows when there is recent food **or** a burn figure: `Burned per day` passes D-6's 3-day floor, or `Burned per session` has at least one window session with an energy row. With recent food, the card is today's card plus D-2/D-7 (fewer than 3 logged days keeps the sentence plus the burn lines; `Burned per session: —` still draws when it has no figure). With no recent food, the card is in **burn-only mode**: the `FUEL` header and the `Last 7 days` line, then only the burn lines that have a figure, in D-7 order. There are no figures, no `{n}/7 days logged` line, no sentence, no split and no dash line. The card is not tappable (no `InkWell`, no button semantics). With neither, `computeFuelSummary` returns `null` and the screen draws no Fuel card. The Stats empty state (no completed session ever) is unchanged and still shows no Fuel card (see Q6). | owner B |
| D-20 | *(Code design, stated.)* `FuelSummary` gains `final bool hasRecentFood` (constructor default `true`, so hand-built test summaries keep today's meaning); burn-only mode = `!hasRecentFood`, with `loggedDays` 0 and every intake average `null`. `computeFuelSummary` no longer returns early on "no recent food". It computes `hasRecentFood`, the per-session burn and the Health average (the reader is called once, under D-11's 5 s timeout, whenever one is passed), then returns `null` only when `!hasRecentFood && burnedKcalAverage == null && burnedPerDayAverage == null`. `StatsScreen` keeps its existing `_fuelSummary != null` gate. In burn-only mode `FuelSection` ignores `onTap`. | owner B |

## Feature Invariants

- Absence is never zero: a figure with no data is either the existing `—` (calorie/protein/carbs/fat figures, Burned per session) or the line is not drawn (split, Burned per day). Never `0 kcal`.
- `lib/features/` and `lib/state/` never import `health_platform_gateway_io.dart` or `package:health`; the plugin stays in the io gateway (web-safety).
- Mock and Hive give the same Fuel figures: every service/screen scenario on a repository runs over `harnessFactories` (Mock and Hive).
- Burned per session's figure for any fixture is bit-for-bit what it was before this PR (D-5); only whether its dash draws in burn-only mode changes (D-19).
- The Fuel card is absent only when it has nothing to show: no recent food and no burn figure (D-19).

## Requirements → Acceptance Criteria

| AC | Requirement | Scenarios |
|---|---|---|
| AC-1 | Split is calories-only, one line, drawn only when both sides have ≥ 2 logged days | S-20801..S-20804 |
| AC-2 | Burn lines no longer hide behind the 3-food-days gate | S-20805, S-20836 |
| AC-3 | Burned per session unchanged | S-20806 |
| AC-4 | Health active-energy read: per local day, merged by the platform store, iOS and Android, web/desktop inert, never throws | S-20820, S-20821, S-20827, S-20828 |
| AC-5 | Settings switch asks once, persists, on iOS and Android only; Info.plist sentence and Android permission present | S-20823, S-20824, S-20826, S-20829, S-20846 |
| AC-6 | Burned per day average over days with data, ≥ 3 days, window d7..d1, DST-safe | S-20830..S-20835 |
| AC-7 | Access off / failure / no gateway hides only that line | S-20837 |
| AC-9 | The card hides only when it has nothing to show; with no recent food it shows only the burn lines with a figure and is not tappable | S-20841..S-20845, S-20848 |
| AC-8 | Wording, order, and screen wiring | S-20839, S-20840 |

## Existing-Functionality Impact

| Touched surface | Readers (grep that found them) | Effect | Guard |
|---|---|---|---|
| `FuelSummary.trainingProteinAverage` / `restProteinAverage` (removed) | `grep -rn "trainingProteinAverage\|restProteinAverage" lib test` → `stats_progress_service.dart:2193,2195`, `fuel_section.dart`, `test/fuel_section_widget_test.dart`, `test/fuel_row_screen_test.dart` (S-1105/S-1106), `test/stats_gallery_render_test.dart:386,388` (untracked, other session) | compile break in each | Phase 1 items 1–6; residue grep in Phase 3 |
| Keys `fuel_split_training` / `fuel_split_rest` (retired) | `grep -rn "fuel_split" lib test docs` → `fuel_section.dart`, `test/fuel_section_widget_test.dart`, `test/fuel_row_screen_test.dart`, `docs/stats_screen.md` | assertions move to `fuel_split` | S-20801..S-20804 |
| `showsAverages` gate around burned line | `grep -rn "showsAverages\|kFuelMinLoggedDays" lib test` → `fuel_section.dart`, `test/fuel_summary_window_test.dart:138,148`, `test/stats_fuel_horizon_screen_test.dart:143`, `test/fuel_section_widget_test.dart` (`S-13434 with only 2 logged days none of the three lines exists`) | that S-13434 test's expectation changes (burned line now present) | S-20805 supersedes it |
| `computeFuelSummary()` signature | `grep -rn "computeFuelSummary" lib test` → `stats_screen.dart:145`; tests call it with no args | optional param, callers unaffected | S-20806 regression |
| Fuel visibility (`kFuelVisibilityDays`) | `stats_progress_service.dart:2131` (early `return null`); `test/fuel_summary_window_test.dart` (`S-17204 visibility: today alone shows, d14 hides, d13 is previous`); `test/fuel_row_screen_test.dart` S-1107 (13 days renders, 14 and 15 hidden; their sessions carry no energy row and Mock seeds none: `grep -rn "SessionEnergy(" lib/mock` → none) | the early return moves after the burn reads (D-20); those fixtures have no burn figure, so they keep their results | S-20845 (guard), D-19 |
| `FuelSection` tap / semantics | `test/fuel_row_screen_test.dart` S-1109, S-1259–S-1261 (`exposes its label and still opens the trend screen`) | unchanged with recent food; burn-only mode drops the `InkWell` | S-20841 |
| Docs that state the old visibility rule | `docs/stats_screen.md:115` (`when recent food exists`), `docs/nutrition.md:55` and `:639`, `docs/records_and_trends.md:71` | rewritten to D-19 | Docs delta |
| Android manifest Health permissions | `android/app/src/main/AndroidManifest.xml:31-32` (`WRITE_EXERCISE`, `READ_WEIGHT`); no test reads it (`grep -rln "READ_WEIGHT" test` → none) | one permission added | S-20846 |
| `HealthPlatformService` | `grep -rn "implements HealthPlatformService" lib test` → 2 lib + 8 test fakes | unaffected (D-12: separate interface) | Phase 2 Done Criteria runs `test/health_platform_test.dart test/health_effort_test.dart` |
| `SettingsState(` ctor | 155 files (`grep -rln "SettingsState(" lib test \| wc -l`) | optional named param, unaffected | full suite at Phase 3 |
| Settings ▸ HEALTH section | `test/health_platform_test.dart:1526-1560` (`healthReadToggleKey`) | new row iOS-only; flutter_test defaults to Android, so existing widget tests see no new row | S-20825 (superseded) |
| Settings ▸ HEALTH section (D-17) | `grep -rln "SettingsScreen(" test` → `screen_widget_test`, `settings_watch_status_test`, `interaction_flow_test`, `settings_diagnostics_test`, `header_standardization_test`, `screen_overflow_contract_test`, `settings_diagnostics_watch_log_test`, `settings_sounds_test`, `health_platform_test`, `settings_scroll_stability_test` | flutter_test's default platform is Android, so **all ten now render the new row**; content below HEALTH moves down by one row (scroll and overflow tests may need a scroll, never a weaker assertion) | S-20829; Phase 2 Done Criteria run all ten |
| `NSHealthShareUsageDescription` | `grep -rn "NSHealthShareUsageDescription" test` → none; `docs/watch-app-setup-and-qa.md:152,172` describe the **watch** target's keys (unaffected) | text appended | S-20826 |
| Fuel-vs-load signal | `grep -rn "FuelSummary\|fuel_summary" lib/core/services/signals` → none | unaffected | — |
| `docs/data_models.md` (51,121 B) | size band 52 KB | FuelSummary paragraph must stay net ≤ +800 B | Phase 1/3 doc items |

## UI Standards Impact

Uses only pieces already on the card (`OmniSurface`, `OmniCardHeader`, the card's `_caption`) and, in Settings, the existing `_SettingsRow`, `Switch`, `_SurfaceDivider`, `_HealthDeniedNotice`. No new exception. `lib/features/settings/settings_screen.dart` carries ratchet entries (`Colors.white` 1, `Colors.black` 2 in `test/helpers/ui_standards_allowlist.dart`): apply "Fix what you touch" (≤ 10 lines each) or list them under "Standards seen, not fixed"; never raise a ratchet.

## Scenarios

Day notation: d0 = today (always outside the window), dk = k days ago, window = d7..d1, d8 = first day outside. Food is seeded with the existing helpers in `test/fuel_row_screen_test.dart` (`_clearConsumedFoods` first: the Mock harness opens with a demo food log), sessions with `_seedSessionOnDay` / `seedSession`. The last column says why each test is red on the base code; "passes with and without the change on purpose" marks a guard and names the mutation it catches.

### Phase 1 — card cleanup

| ID | Fixture | Expected | Fails without the change because |
|---|---|---|---|
| S-20801 | split shown (supersedes S-1105 text): S-1105's fixture: food d1..d7 = 200,300,…,800 kcal (dk = 100·(k+1)); completed sessions d1, d3; a **running** rolling session d5 | model `trainingLoggedDays` 2, `restLoggedDays` 5, training (200+400)/2 = 300, rest (300+500+600+700+800)/5 = 580; caption `fuel_split` = `Training days 300 · Rest days 580 kcal`; no rendered text contains `protein` except the `Protein` label; keys `fuel_split_training` / `fuel_split_rest` absent | today two captions read `Training days: 300 kcal · 30 g protein` / `Rest days: 580 kcal · 58 g protein` and `fuel_split` does not exist |
| S-20802 | trained every logged day (supersedes S-1106 "rest side reads a dash"): food d1 100, d3 300, d5 500 kcal; completed sessions d1, d3, d5 | training 3 days, rest 0 → no `fuel_split` widget, no text containing `Rest days` or a `—` split line; model `restCaloriesAverage` null, `restLoggedDays` 0 | today `Rest days: —` is drawn |
| S-20803 | no training day (supersedes S-1106 "training side reads a dash"): food d1 100, d3 300, d5 500; completed sessions only on d0 (today) and d8 | training 0 days → no `fuel_split` | today `Training days: —` is drawn |
| S-20804 | the ≥ 2 boundary: (a) food d1 2000, d2 1000, d3 1800, d4 1600; sessions d1, d2 → `Training days 1500 · Rest days 1700 kcal`. (b) food d1..d5 = 2000; sessions d1 and d6 (d6 has **no food**) → training logged days 1 → no split. | (a) drawn; (b) absent, model `trainingLoggedDays` 1 | (b) today both split captions draw for any day counts; (a) the one-line text does not exist |
| S-20805 | burn line without enough food (supersedes `S-13434 with only 2 logged days none of the three lines exists`): hand-built `FuelSummary(loggedDays: 2, burnedKcalAverage: 300, burnedSessionCount: 1)` | `fuel_not_enough_days` sentence, `2/7 days logged`, and `Burned per session: 300 kcal · 1 session` present; no `fuel_split` | today the burned caption sits inside the `showsAverages` block and is absent at 2 logged days |
| S-20806 | Burned per session regression: the existing `test/fuel_burned_summary_test.dart` S-13430..S-13433 fixtures (today/d8/rolling excluded, estimate flag, sessions without an energy row, day edges) | every existing assertion green, file **not edited** | passes with and without the change on purpose: regression guard for D-5 (mutation: drop the `~` rule, S-13431 goes red) |

### Phase 2 — Health read and permission

| ID | Fixture | Expected | Fails without the change because |
|---|---|---|---|
| S-20820 | bucketing: `activeEnergyTotalsByDay(dayStarts: [2026-11-02 … 2026-11-08 midnights], points)` with points (dateFrom, kcal): (11-08 00:00, 512.4); (11-07 09:00, 300) and (11-07 18:00, 200); (11-06 10:00, 0); (11-09 00:00, 999) — next day; (11-01 23:59, 999) — before the window; one non-numeric point on 11-05 | `{11-08: 512.4, 11-07: 500.0, 11-06: 0.0}` (keys = midnight ms); no key for 11-05, 11-04, 11-03, 11-02 | `activeEnergyTotalsByDay` does not exist (compile red) |
| S-20821 | DST day bounds: `activeEnergyDayBounds(day)` for the day of the first 2026 DST change found by the loop in `test/stats_dst_day_arithmetic_test.dart`, and for 2026-11-10 | DST day: end = next local midnight (`hour == 0`), interval 82,800 or 90,000 s; ordinary day: 86,400 s. Skipped in a zone without DST; run with `TZ=America/New_York` | `activeEnergyDayBounds` does not exist; a fixed 86,400 s interval would put the DST day off midnight |
| S-20822 | **SUPERSEDED by S-20827 and S-20828 (owner 2026-11-17); do not build.** non-iOS and web are inert: `HealthPluginPlatformService(isIOS: false)`; `UnavailableHealthPlatformService()` | `readDailyActiveEnergy([...7 days])` → `{}`, `requestActiveEnergyReadPermission()` → `false`, for both; no plugin call (no channel mock needed) | the gateways do not implement `HealthActiveEnergySource` (compile red) |
| S-20823 | switch lifecycle (plain `test()`, Mock and Hive): fake `HealthActiveEnergySource` counting permission calls, answering `true`; then a second fake answering `false` | default `healthReadActiveEnergy == off`; enable → 1 call, `on`, pref `health.readActiveEnergy` = `on`; a new `SettingsState` on the same repo after `initialize()` reads `on`; disable → `off`, 0 further calls; refusing fake → `permissionDenied`, pref `denied`; `healthReadBodyWeight` untouched throughout | `setHealthReadActiveEnergyEnabled` and the `health.readActiveEnergy` preference do not exist |
| S-20824 | read gate: switch `off` + fake source returning `{d1: 500}` | `settingsState.readDailyActiveEnergy(days)` → `{}`, source read 0 times; switch `on` → `{d1: 500}`, 1 read; no source (null) + `on` → `{}` | `SettingsState.readDailyActiveEnergy` does not exist |
| S-20825 | **SUPERSEDED by S-20829 (owner 2026-11-17); do not build.** row is iOS-only (Mock-first `testWidgets`): Settings screen pumped with `debugDefaultTargetPlatformOverride = TargetPlatform.iOS`, then `.android` (reset in `tearDown`) | iOS: row `Read active energy` with the D-9 subtitle and `healthReadActiveEnergyToggleKey`, below `Read body weight`; Android: no such key; `Read body weight` row and subtitle unchanged in both | the `Read active energy` row does not exist |
| S-20826 | permission sentence: read `ios/Runner/Info.plist` as text | `NSHealthShareUsageDescription` string ends with the D-10 sentence and still starts with `OmniTrain reads your body weight from Apple Health` | the Info.plist string has no active-energy sentence |
| S-20827 | per-day read on both platforms (supersedes the iOS-only half of S-20822): `HealthPluginPlatformService(isIOS: true, dayQuery: fake)` and `(isIOS: false, dayQuery: fake)` over the 7 days 2026-11-02..11-08. The iOS fake returns buckets only for 11-08 (512.4) and 11-07 (500). The Android fake returns one bucket for **every** day, 0 on all but 11-08 (512.4) and 11-07 (500), and throws for 11-05. A third fake throws before the first day (Health Connect not installed). | the fake is called once per day with `(midnight, next midnight, length in seconds)`; both platforms return 11-08: 512.4 and 11-07: 500.0; Android's 0 days are carried as `0.0` and dropped later by D-6; 11-05 is absent; the throwing-first fake gives `{}` and no exception | the gateway has no Android read and no `dayQuery` seam |
| S-20828 | web and desktop are inert (supersedes S-20822): `UnavailableHealthPlatformService()`; `createHealthPlatformService()` on the macOS test host | `readDailyActiveEnergy` → `{}`, `requestActiveEnergyReadPermission()` → `false`; the host factory returns the unavailable gateway | `UnavailableHealthPlatformService` does not implement `HealthActiveEnergySource` (compile red) |
| S-20829 | row on iOS and Android, absent elsewhere (supersedes S-20825), Mock-first `testWidgets`: Settings pumped with `debugDefaultTargetPlatformOverride` = `iOS`, `android`, `macOS` (reset in `tearDown`) | iOS and Android: `Read active energy` row with D-9's subtitle and `healthReadActiveEnergyToggleKey`, below `Read body weight`; macOS: no such key; `Read body weight` unchanged on all three | the row does not exist |
| S-20846 | Android permission: read `android/app/src/main/AndroidManifest.xml` as text | contains `android.permission.health.READ_ACTIVE_CALORIES_BURNED` exactly once, and `READ_WEIGHT` and `WRITE_EXERCISE` are still present | the manifest has no active-calories permission |
| S-20850 | startup wiring (added in the build): `runStartup(createHealthPlatformGateway: ...)` with (a) a gateway that implements `HealthActiveEnergySource` and counts permission asks, (b) a weight-only gateway; then `settingsState.setHealthReadActiveEnergyEnabled(true)` | (a) exactly 1 ask, state `on`; (b) state `permissionDenied` | `main.dart` passed no `activeEnergySource`, so the real app's switch would always resolve to denied (test passes only with the wiring line: its removal is a killed mutant) |

### Phase 3 — Burned per day

Fake reader = a closure returning a fixed `Map<int, double>` keyed by day-start ms and recording the `dayStarts` it was called with.

| ID | Fixture | Expected | Fails without the change because |
|---|---|---|---|
| S-20830 | seven days: d1 520, d2 480, d3 610, d4 450, d5 530, d6 500, d7 550 | 3640 / 7 = 520.0 → `Burned per day: 520 kcal · active, all movement` | `burnedPerDayAverage` and the `fuel_burned_day` caption do not exist |
| S-20831 | exactly 3 days: d1 600, d3 400, d5 500 only | 1500 / 3 = 500.0, line shown | same as S-20830; also pins that exactly 3 days is enough (mutation: `> 3` hides it) |
| S-20832 | exactly 2 days: d1 600, d2 400 only | `burnedPerDayAverage` null, no `fuel_burned_day` | passes with and without the change on purpose: guards the 3-day floor (mutation: floor 2 shows 500) |
| S-20833 | zero, NaN and negative are no data: d1 600, d2 0, d3 400, d4 500, d5 NaN, d6 -10 | (600+400+500)/3 = 500.0; counting the zero would give 375.0 | no Health average exists today; a `>= 0` mutation reads 375 |
| S-20834 | window edges: reader returns d0 999, d8 999, d1 300, d4 450, d7 600 | (300+450+600)/3 = 450.0; recorded `dayStarts` = exactly [d7, d6, …, d1] local midnights | no reader is called today; a mutation that includes d0 (or d8) reads (300+450+600+999)/4 = 587 |
| S-20835 | DST window: `fuelWindowDayStarts(today)` with today = (day after first 2026 DST change) + 3 days | 7 values, each `hour == 0 && minute == 0`, consecutive calendar days, last = today − 1 day; skipped without DST | `fuelWindowDayStarts` does not exist; a 24 h step drifts to 23:00 or 01:00 |
| S-20836 | independent of food gate: food on d1, d2 only (2 days) + S-20830 reader | sentence + `2/7 days logged` + `Burned per day: 520 kcal …` | no Health line exists; a mutation that gates it on `showsAverages` hides it |
| S-20837 | failure hides only this line (plain `test()`): (a) reader throws; (b) reader never completes, timeout injected as 50 ms | summary returned; `burnedPerDayAverage` null; every other field equals the same fixture computed with no reader | no reader exists; without the catch/timeout the summary throws or never returns |
| S-20838 | **SUPERSEDED by S-20848 (owner 2026-11-17); do not build.** no food, Health data: no food in the last 14 days, S-20830 reader | `computeFuelSummary` returns null (no card) — D-4 | passes with and without the change on purpose: guards D-4 card visibility (mutation: Health data alone makes a card) |
| S-20839 | order and wording: hand-built summary: loggedDays 7, training 2022/rest 1850 with 3/4 days, per-day 519.5, per-session 89 over 9, not estimated | captions top to bottom: `7/7 days logged`, `Training days 2022 · Rest days 1850 kcal`, `Burned per day: 520 kcal · active, all movement`, `Burned per session: 89 kcal · 9 sessions` (assert by vertical position) | today the order is split pair then burned, with protein; `fuel_burned_day` does not exist |
| S-20840 | screen wiring (Mock-first `testWidgets`): Mock repo; pref `health.readActiveEnergy` = `on` seeded in `setUp`; `SettingsState` built with a fake source returning S-20830's map (synchronous `Future.value`, no delay); food d1..d3 | `StatsScreen` shows `Burned per day: 520 kcal · active, all movement`; with pref `off` the same screen has no `fuel_burned_day` and identical other Fuel captions | `StatsScreen` passes no reader, so no `fuel_burned_day` appears |
| S-20841 | no food, session burn only, not tappable: no food in the last 14 days; completed sessions on d2 (energy row 300, measured) and d4 (energy row 500, estimated); reader `null`. Screen test (Mock-first): tap the card. | summary not null, `hasRecentFood` false, `burnedKcalAverage` 400.0; the card shows `FUEL`, `Last 7 days` and `Burned per session: ~400 kcal · 2 sessions` only; no `fuel_logged_days`, `fuel_not_enough_days`, figure, split or `fuel_burned_day`; no `fuel_row` `InkWell`, no button semantics; the tap pushes no route (still on Stats) | today `computeFuelSummary` returns null when there is no recent food, so there is no card |
| S-20842 | nothing to show, card absent: no food in the last 14 days and no session with an energy row in the window (one completed session on d3 **without** an energy row). (a) reader returns d1 600, d2 400 (2 days); (b) reader returns S-20830's 7 days but the switch is `off` (the screen test passes `settingsState.readDailyActiveEnergy`, which returns `{}`) | (a) `computeFuelSummary` → null; (b) the Stats screen has no `fuel_section` | passes with and without the change on purpose: guards the "nothing at all" rule (mutation: show the card whenever a reader exists, both go red) |
| S-20843 | recent food, no burn at all: food d1..d3 = 2000; no energy rows; reader returns `{}` | today's card: figures, `3/7 days logged`, `Burned per session: —` (the existing dash rule), no `fuel_burned_day`, no other dash line | passes with and without the change on purpose: guards D-19's "with recent food the card is today's card" (mutation: drop the per-session dash everywhere) |
| S-20844 | burn-only with both lines: no food in 14 days; S-20830 reader; S-20841's two sessions | lines in order `Burned per day: 520 kcal · active, all movement`, `Burned per session: ~400 kcal · 2 sessions` | no card exists today without recent food |
| S-20845 | the 14-day boundary, no burn: (a) the only food is on d13; (b) the only food is on d14; no energy rows, reader `{}` | (a) card shown with `0/7 days logged` (recent food); (b) `computeFuelSummary` → null | passes with and without the change on purpose: pins today's `kFuelVisibilityDays` rule through the moved return (mutation: `d14` counted, (b) goes red) |
| S-20848 | no food, Health burn only (supersedes S-20838): no food in the last 14 days; no session energy rows; S-20830 reader | summary not null, `hasRecentFood` false; the card shows `Last 7 days` and `Burned per day: 520 kcal · active, all movement` only; no `Burned per session` line (no dash in burn-only mode) | today the summary is null with no recent food |
| S-20849 | empty state keeps no Fuel card (added in the build, D-19 / Q6): no completed session ever, food d1..d3 = 2000, switch on, 7 days of Health energy | no `fuel_section` (the `_totalSessions == 0` branch renders the welcome state) | passes with and without the change on purpose: guards Q6's default (mutation: render the Fuel card in the empty branch) |
| S-20851 | model default (added in the build, from the mutation pass): `FuelSummary(...)` built without `hasRecentFood`; and a burn-only summary that still carries intake averages | the first is the normal card (figures, `fuel_row` tappable once); the second draws no figure, no logged-days line, no sentence | the `hasRecentFood` default was unobserved by any test (mutation: default `false`), and the burn-only branch for the figures block was unguarded (mutation: drop `!_burnOnly`) |

## Phases

Iteration 1.

Baseline (implementer, before the first edit of Phase 1): record `flutter analyze` issue count and the red/green state of every test file named in this plan in `2026-11-15-208-fuel-burned-per-day-plan.evidence.md`. Every new scenario test is shown red on the base code first (write the test first and run it against the unchanged source, or set your own edit aside by hand and restore it; never `git stash` in this shared tree), except the guards ("passes with and without the change on purpose").

### Phase 1: calories-only split and burn lines outside the food gate (@developer)

1. [ ] D-2/D-3: add `kFuelMinSplitDays = 2`; replace the two protein split fields with `trainingLoggedDays` / `restLoggedDays` (required ints); add a `showsSplit` getter implementing D-2 — `lib/core/models/fuel_summary.dart` · `FuelSummary`
2. [ ] Fill the new counts from the existing `training` / `rest` lists; stop computing protein split — `lib/core/services/stats_progress_service.dart` · `computeFuelSummary` (Fuel region only, D-15)
3. [ ] D-1/D-2/D-19: replace `_split` and the two split captions with one `fuel_split` caption under `showsSplit`; move the `fuel_burned` caption out of the `showsAverages` block, after the split; update the class doc comment — `lib/features/stats/widgets/fuel_section.dart` · `FuelSection`
4. [ ] S-20805, S-20839-shape helpers: update `_summary` helper fields; rewrite the split/burned assertions (`S-13434 …` tests) to the new text; add S-20802/S-20803/S-20805 widget cases — `test/fuel_section_widget_test.dart`
5. [ ] S-20801..S-20804 on both harnesses: rewrite S-1105/S-1106 assertions to the new text/absence (test names gain the S-2080x id), add S-20804 — `test/fuel_row_screen_test.dart`
6. [ ] Delete only the `trainingProteinAverage:` and `restProteinAverage:` arguments; touch nothing else (other session's untracked file) — `test/stats_gallery_render_test.dart` · `FuelSummary(` call
7. [ ] Docs, zero lag: "Training days and rest days" and "Not enough logged days"/"Burned per session" paragraphs (new wording, the ≥ 2 rule, burn line outside the gate, renamed test names) — `docs/stats_screen.md` (43 KB); FuelSummary paragraph (net ≤ +300 B) — `docs/data_models.md` (51.1 KB); `computeFuelSummary` verified-by list — `docs/nutrition.md` (43.9 KB)

**Done Criteria** (run until green; paste counts in evidence):
- `bash .claude/scripts/macos/with-timeout.sh 600 flutter test test/fuel_section_widget_test.dart test/fuel_row_screen_test.dart test/fuel_summary_window_test.dart test/fuel_burned_summary_test.dart test/stats_fuel_horizon_screen_test.dart test/stats_gallery_render_test.dart` (widget files Mock-first: run `--plain-name "Mock"` first if a Hive group stalls)
- `bash .claude/scripts/macos/with-timeout.sh 300 flutter analyze` — issue count ≤ baseline
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty
- `grep -rn "trainingProteinAverage\|restProteinAverage\|fuel_split_training\|fuel_split_rest\|g protein" lib test` → empty

**Predicted Files**: `lib/core/models/fuel_summary.dart`, `lib/core/services/stats_progress_service.dart`, `lib/features/stats/widgets/fuel_section.dart`, `test/fuel_section_widget_test.dart`, `test/fuel_row_screen_test.dart`, `test/stats_gallery_render_test.dart`, `docs/stats_screen.md`, `docs/data_models.md`, `docs/nutrition.md`, plus this plan's evidence file.

### Phase 2: daily active-energy read (Apple Health and Health Connect) and the Settings switch (@developer)

1. [ ] D-12: `HealthActiveEnergySource` interface; `UnavailableHealthPlatformService` implements it (`{}` / `false`) — `lib/core/services/health_platform_service.dart`
2. [ ] D-14/D-18: `activeEnergyDayBounds`, `activeEnergyTotalsByDay` (pure); `HealthPluginPlatformService` gains the `dayQuery` seam and implements the interface (per-day interval query on iOS and Android; `ACTIVE_ENERGY_BURNED` read permission via `_requestPermission`) — `lib/core/services/health_platform_gateway_io.dart`
3. [ ] D-9: `HealthPrefs.readActiveEnergyKey = 'health.readActiveEnergy'` — `lib/core/constants/health_constants.dart`
4. [ ] D-9/D-13: optional `activeEnergySource` ctor param; `healthReadActiveEnergy` getter, load in `initialize`, `setHealthReadActiveEnergyEnabled(bool)` via `_resolveHealthToggle`, `readDailyActiveEnergy(List<DateTime>)` gate — `lib/state/settings/settings_state.dart`
5. [ ] D-17: `Read active energy` row on iOS and Android + denied notice + `healthReadActiveEnergyToggleKey` — `lib/features/settings/settings_screen.dart` · `_HealthSection`
6. [ ] D-12: pass `activeEnergySource:` (the gateway when it `is HealthActiveEnergySource`) — `lib/main.dart` · `SettingsState(` call; D-10 sentence — `ios/Runner/Info.plist`; D-16 permission and comment — `android/app/src/main/AndroidManifest.xml`
7. [ ] S-20820, S-20821, S-20823, S-20824, S-20826, S-20827, S-20828, S-20846 — new `test/health_active_energy_read_test.dart` (pure + gateway + SettingsState + file checks, plain `test()`, Mock and Hive for S-20823) and S-20829 — `test/health_active_energy_settings_screen_test.dart` (Mock-first)
8. [ ] Docs: HEALTH paragraph (third switch, iOS and Android, read refusals invisible on iOS, Health Connect missing = no line, Android unverified on device) — `docs/theme_and_settings.md` (12.4 KB); gateway bullets + `HealthActiveEnergySource` — `docs/state_management/services_and_utils.md` (47.2 KB, add ≤ 1.5 KB); `SettingsState(...)` line — `docs/navigation_and_screens.md:248`

**Done Criteria**:
- `bash .claude/scripts/macos/with-timeout.sh 600 flutter test test/health_active_energy_read_test.dart test/health_active_energy_settings_screen_test.dart test/health_platform_test.dart test/health_effort_test.dart test/health_effort_native_test.dart test/health_yoga_kind_test.dart`
- `bash .claude/scripts/macos/with-timeout.sh 600 flutter test test/screen_widget_test.dart test/settings_watch_status_test.dart test/interaction_flow_test.dart test/settings_diagnostics_test.dart test/header_standardization_test.dart test/screen_overflow_contract_test.dart test/settings_diagnostics_watch_log_test.dart test/settings_sounds_test.dart test/settings_scroll_stability_test.dart` (the ten Settings readers, D-17; Mock-first)
- `TZ=America/New_York flutter test test/health_active_energy_read_test.dart --plain-name "S-20821"` → 1 passed, not skipped
- `bash .claude/scripts/macos/with-timeout.sh 300 flutter analyze` — ≤ baseline
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `grep -rln "package:health/" lib | grep -v health_platform_gateway_io.dart` → empty
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty

**Predicted Files**: `lib/core/services/health_platform_service.dart`, `lib/core/services/health_platform_gateway_io.dart`, `lib/core/constants/health_constants.dart`, `lib/state/settings/settings_state.dart`, `lib/features/settings/settings_screen.dart`, `lib/main.dart`, `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`, `test/health_active_energy_read_test.dart` (new), `test/health_active_energy_settings_screen_test.dart` (new), `docs/theme_and_settings.md`, `docs/state_management/services_and_utils.md`, `docs/navigation_and_screens.md`. Not touched: `health_platform_gateway_stub.dart` (it already returns `UnavailableHealthPlatformService`).

### Phase 3: the Burned per day line and the burn-only card (@developer)

1. [ ] D-6/D-7/D-20: `kFuelMinActiveEnergyDays = 3`; fields `double? burnedPerDayAverage` (default null), `bool hasRecentFood` (default true); `bool get showsBurnedPerDay` — `lib/core/models/fuel_summary.dart`
2. [ ] D-6/D-11/D-13: `fuelWindowDayStarts`, `averageActiveEnergy`, `kFuelActiveEnergyTimeout` (overridable in tests via an optional param); `computeFuelSummary({readDailyActiveEnergy})` calls the reader once with `fuelWindowDayStarts(today)`, catches errors/timeout → null; D-19/D-20: move the "no recent food" `return null` after both burn reads and return null only when nothing is left — `lib/core/services/stats_progress_service.dart` (Fuel region only)
3. [ ] D-7: `fuel_burned_day` caption between split and `fuel_burned`, outside the food gate; D-19: burn-only mode (`!hasRecentFood`: header, `Last 7 days`, burn lines that have a figure, no `InkWell` / button `Semantics`) — `lib/features/stats/widgets/fuel_section.dart`
4. [ ] D-13: pass `widget.settingsState.readDailyActiveEnergy` — `lib/features/stats/stats_screen.dart` · `_loadData`
5. [ ] S-20830..S-20837, S-20841..S-20845 (service halves), S-20848 (plain `test()`, Mock and Hive) — new `test/fuel_burned_per_day_test.dart`; S-20839 and burn-only rendering of S-20841/S-20844/S-20848 — `test/fuel_section_widget_test.dart`; S-20840, the S-20841 tap and S-20842(b) — new `test/fuel_burned_per_day_screen_test.dart` (Mock-first)
6. [ ] Docs: new "Burned per day" and "Burn-only card" paragraphs in the Fuel row section and the visibility sentence at `docs/stats_screen.md:115`; FuelSummary paragraph (keep `docs/data_models.md` < 52,000 B); `computeFuelSummary` section, line 55 and test table row in `docs/nutrition.md`; the Nutrition-entry reason at `docs/records_and_trends.md:71` (10.4 KB)
7. [ ] Residue sweep (below) and full suite

**Done Criteria**:
- `bash .claude/scripts/macos/with-timeout.sh 600 flutter test test/fuel_burned_per_day_test.dart test/fuel_burned_per_day_screen_test.dart test/fuel_section_widget_test.dart test/fuel_row_screen_test.dart test/fuel_summary_window_test.dart test/fuel_burned_summary_test.dart test/stats_fuel_horizon_screen_test.dart`
- `TZ=America/New_York flutter test test/fuel_burned_per_day_test.dart --plain-name "S-20835"` → passed, not skipped
- `bash .claude/scripts/macos/with-timeout.sh 900 flutter test` — no new red versus the baseline (list any pre-existing red, e.g. other sessions' files)
- `bash .claude/scripts/macos/with-timeout.sh 300 flutter analyze` — ≤ baseline
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- Residue: `grep -rn "trainingProteinAverage\|restProteinAverage\|fuel_split_training\|fuel_split_rest\|Rest days: \|Training days: " lib test docs --exclude-dir=plans` → empty; `wc -c docs/data_models.md docs/stats_screen.md docs/nutrition.md docs/state_management/services_and_utils.md` → each < 52,000

**Predicted Files**: `lib/core/models/fuel_summary.dart`, `lib/core/services/stats_progress_service.dart`, `lib/features/stats/widgets/fuel_section.dart`, `lib/features/stats/stats_screen.dart`, `test/fuel_burned_per_day_test.dart` (new), `test/fuel_burned_per_day_screen_test.dart` (new), `test/fuel_section_widget_test.dart`, `docs/stats_screen.md`, `docs/data_models.md`, `docs/nutrition.md`, `docs/records_and_trends.md`.

## Docs delta

Markers are phrases on one line of the doc. Sizes today: `docs/records_and_trends.md` 10,422 B, `docs/stats_screen.md` 43,040 B, `docs/data_models.md` 51,121 B (keep < 52,000), `docs/nutrition.md` 43,871 B, `docs/theme_and_settings.md` 12,396 B, `docs/state_management/services_and_utils.md` 47,208 B, `docs/navigation_and_screens.md` 30,185 B.

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/stats_screen.md` | MODIFIED | A side with no logged day reads a dash rather than a zero. | `kFuelMinSplitDays` | D-2, S-20802 |
| `docs/stats_screen.md` | MODIFIED | `showsAverages` block as the two split lines | outside the food-days gate | D-19, S-20805 |
| `docs/stats_screen.md` | MODIFIED | their comparisons, the two split lines and the burned-per-session line | the split line; the logged-days line and both burn lines always draw | D-19, S-20836 |
| `docs/stats_screen.md` | ADDED | - | **Burned per day.** | D-6, D-7, S-20830 |
| `docs/data_models.md` | MODIFIED | rest split of each; the mean active kcal per finished session in the window | `trainingLoggedDays` | D-3, S-20801 |
| `docs/data_models.md` | ADDED | - | `burnedPerDayAverage` | D-6, S-20830 |
| `docs/nutrition.md` | ADDED | - | `readDailyActiveEnergy` | D-13, S-20834 |
| `docs/nutrition.md` | ADDED | - | Burned per day averages Apple Health or Health Connect active energy over the days with data | D-6, S-20833 |
| `docs/theme_and_settings.md` | ADDED | - | Read active energy | D-17, S-20829 |
| `docs/state_management/services_and_utils.md` | ADDED | - | `HealthActiveEnergySource` | D-12, D-18, S-20827 |
| `docs/stats_screen.md` | MODIFIED | [Fuel row](#fuel-row) when recent food exists, and the | or a burn figure | D-19, S-20841 |
| `docs/stats_screen.md` | ADDED | - | **Burn-only card.** | D-19, S-20848 |
| `docs/nutrition.md` | MODIFIED | entries: the Stats screen's Fuel row (hidden once food has not been logged for | stops opening the trend | D-19, S-20841 |
| `docs/nutrition.md` | MODIFIED | Stats screen's four-week window, and the summary is `null` unless some logged | nothing to show | D-19, S-20842 |
| `docs/records_and_trends.md` | MODIFIED | screen's Fuel row hides once food has not been logged for a while, which would | stops opening the trend | D-19, S-20841 |
| `docs/theme_and_settings.md` | ADDED | - | Health Connect | D-16, S-20846 |
| `docs/navigation_and_screens.md` | MODIFIED | SettingsState(repository, preferencesService, healthPlatform: createHealthPlatformService()) | activeEnergySource | D-12, S-20823 |

## Owner device checks (after Phase 3; iPhone with Apple Watch, plus one Android row)

1. Settings ▸ HEALTH shows `Read active energy` (iPhone only). Switch it on: Health's sheet lists Active Energy to read; the top text includes "It also reads your active energy so the Stats screen can show the calories you burn per day."
2. Open Stats. Compare `Burned per day` with Health ▸ Activity ▸ Active Energy for the 7 days before today (today excluded), averaging only days with a value: should match within 1 kcal of rounding.
3. Health ▸ Sharing ▸ Apps ▸ OmniTrain: turn Active Energy off, reopen Stats: the line is gone, the rest of the card is unchanged.
4. A week with fewer than 3 watch-worn days: the line is hidden.
5. A week trained every day: no Training/Rest line and no dash.
6. A fortnight with no food logged but a workout in the last 7 days: the Fuel card shows `Last 7 days` and only the burn lines (no food figures, no dash), and tapping it does nothing.
7. No food in the last 14 days, no workout with calories in the last 7 days, and `Read active energy` off: no Fuel card at all.
8. **Android (unverified on device; the owner cannot run Android):** Settings ▸ HEALTH shows `Read active energy`; switching it on opens Health Connect's sheet for Active calories burned; Stats shows `Burned per day`; without Health Connect installed the line is absent. Covered only by host tests (S-20827, S-20829, S-20846).
9. **(owner)** With `Read active energy` on, open Stats a few times: it opens as quickly as before (the Health read runs while the screen loads; the longest it can add is 5 seconds if Health is slow).

## Files Affected

Production: `lib/core/models/fuel_summary.dart`, `lib/core/services/stats_progress_service.dart`, `lib/features/stats/widgets/fuel_section.dart`, `lib/features/stats/stats_screen.dart`, `lib/core/services/health_platform_service.dart`, `lib/core/services/health_platform_gateway_io.dart`, `lib/core/constants/health_constants.dart`, `lib/state/settings/settings_state.dart`, `lib/features/settings/settings_screen.dart`, `lib/main.dart`, `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml` (predicted production diff ≈ 330 lines). Readers only, unchanged: `lib/core/services/health_platform_gateway_stub.dart`, `lib/core/services/health_platform_gateway.dart`, the 8 `HealthPlatformService` test fakes.

## Notes

- Dependency graph: Phase 1 → Phase 3 (shares `FuelSummary` and the card); Phase 2 → Phase 3 (reader). Phases 1 and 2 are independent and may run in either order or in parallel; running Phase 2 first gives nothing visible until Phase 3.
- Intermediate states: after Phase 1 the card has the new split and the per-session line outside the food gate, no Health line. After Phase 2 the Settings switch exists but nothing reads its data yet (the switch works and asks Health). After Phase 3 the feature is complete.
- Intermediate state added by D-19: burn-only mode exists only after Phase 3; Phases 1 and 2 leave today's visibility rule in place.
- Q-answers that change the build: Q5 "14 days ago counts" → supersede D-19's boundary (`kFuelVisibilityDays` 15) before Phase 3; Q6 "show it" → a new decision for the empty state before Phase 3. Earlier: Q1 "no" → keep both burn lines inside `showsAverages`; Q2 "1" → `kFuelMinSplitDays = 1`; Q3 "ask on Stats" → supersede D-9 before Phase 2; Q4 "show day count" → supersede D-7 before Phase 3.

## Questions (one batched round; defaults in force)

- Q1. Should both burn lines show even when fewer than 3 days of food are logged? Default **yes** (D-4). *Moot after D-19.*
- Q2. How many logged days must each side have before Training/Rest shows? Default **2 each** (D-2).
- Q3. Where is Health permission asked? Default **a new `Read active energy` switch in Settings ▸ Health**, like `Read body weight`; Stats never prompts (D-9).
- Q4. Should `Burned per day` say how many days it averaged (e.g. `· 5 days`)? Default **no**, the owner's wording as given (D-7).

Second round (2026-11-17), observable behaviour only:
- Q5. The owner wrote "food 14 days ago still counts, 15 does not". Today's rule, which the owner also said to keep, counts 13 days ago and not 14 (the last 14 days including today). Default: **keep today's rule** (D-19, S-20845).
- Q6. A brand-new user with no finished workout ever sees only the Stats empty state. Should Health "Burned per day" alone bring up the Fuel card there? Default: **no**, the empty state stays as it is (D-19).

## Progress

- [x] Phase 1 (1a production, 1b tests, docs)
- [x] Phase 2 (2a read + state + wiring, 2b Settings row, 2c startup wiring test, Info.plist and manifest by the governor)
- [x] Phase 3 (3a production, 3b service tests, 3c1 widget tests, 3c2 screen tests, docs)
- [x] Review: APPROVE WITH FIXES, 2 minors (doc wording), both fixed by the governor
- [ ] Owner device checks 1-8

## Assumption Log

- Q5 default taken (owner to confirm): the 14-day food rule stays as today, so food 13 days ago counts and 14 days ago does not (S-20845). Ratified by the review.
- Q6 default taken (owner to confirm): a brand-new user with no finished workout sees only the Stats welcome screen, no Fuel card (S-20849). Ratified.
- Derived rulings stand: a Health day reading 0 is no data; numbers print without a thousands separator (`2022`); no food in 14 days and no burn figure means no card.
- Governor-written (outside the builders' write ceiling or after the mutation pass): the `Info.plist` sentence (D-10), the Android manifest permission (D-16), three tests-only additions (S-20824 denied arm, S-20851 and the burn-only figures test), two stale-claim doc fixes (`docs/widget_catalog.md`, `docs/state_management/app_state.md`), two review-minor doc fixes (`docs/nutrition.md`, `docs/stats_screen.md`; the plan's Docs delta marker follows the new nutrition wording).
- Stats opens through a fresh `StatsScreen` each time (pushed from Home), so the Health read happens on every open; a Health store that hangs delays the screen by at most the 5 s limit (D-11). Owner check 9 below.

## Feedback
